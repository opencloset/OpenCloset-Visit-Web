#!/usr/bin/env perl

use v5.18;
use Mojolicious::Lite;

#
# redirect to login rather than not found page
#
#   https://groups.google.com/forum/#!topic/mojolicious/UbY9Ac9unfY
#   https://github.com/kraih/mojo/compare/69fbd6807611ec209eff4147b511c8c324a80118...d9145abedbbebe226f9f6f3b22488de88809ba4d
#
{
    package OpenCloset::Web::Controller;

    use base 'Mojolicious::Controller';

    sub render_not_found {
        my ( $self, $e ) = @_;

        if ( !$self->is_user_authenticated ) {
            $self->redirect_to( $self->url_for('/visit') );
            return;
        }

        Mojolicious::Controller::_development( 'not_found', @_ );
    }

    1;
}
app->controller_class("OpenCloset::Web::Controller");

use CHI;
use Data::Pageset;
use DateTime::Duration;
use DateTime::Format::Duration;
use DateTime::Format::Human::Duration;
use DateTime;
use Encode 'decode_utf8';
use Gravatar::URL;
use HTTP::Tiny;
use List::MoreUtils qw( zip );
use List::Util qw( sum );
use Mojo::Util qw( encode );
use Parcel::Track;
use SMS::Send::KR::APIStore;
use SMS::Send::KR::CoolSMS;
use SMS::Send;
use Statistics::Basic;
use String::Random;
use Try::Tiny;
use Unicode::GCString;
use Unicode::Normalize;

use Postcodify;

use OpenCloset::Schema;
use OpenCloset::Size::Guess;

app->defaults( %{ plugin 'Config' => { default => {
    jses        => [],
    csses       => [],
    breadcrumbs => [],
    active_id   => q{},
    page_id     => q{},
    alert       => q{},
    type        => q{},
}}});

my $CACHE = CHI->new(
    driver   => 'File',
    root_dir => app->config->{cache}{dir} || './cache',
);
app->log->info( "cache dir: " . $CACHE->root_dir );

my $DB = OpenCloset::Schema->connect({
    dsn      => app->config->{database}{dsn},
    user     => app->config->{database}{user},
    password => app->config->{database}{pass},
    %{ app->config->{database}{opts} },
});

plugin 'validator';
plugin 'haml_renderer';
plugin 'FillInFormLite';

plugin 'authentication' => {
    autoload_user => 1,
    load_user     => sub {
        my ( $app, $uid ) = @_;

        my $user_obj = $DB->resultset('User')->find({ id => $uid });

        return $user_obj
    },
    session_key   => 'access_token',
    validate_user => sub {
        my ( $self, $user, $pass, $extradata ) = @_;

        my $user_obj = $DB->resultset('User')->find({ email => $user });
        unless ($user_obj) {
            app->log->warn("cannot find such user: $user");
            return;
        }

        #
        # GitHub #199
        #
        # check expires when login
        #
        my $now = DateTime->now( time_zone => app->config->{timezone} )->epoch;
        unless ( $user_obj->expires && $user_obj->expires > $now ) {
            app->log->warn( "$user\'s password is expired" );
            return;
        }

        unless ( $user_obj->check_password($pass) ) {
            app->log->warn("$user\'s password is wrong");
            return;
        }

        unless ( $user_obj->user_info->staff ) {
            app->log->warn("$user is not a staff");
            return;
        }

        return $user_obj->id;
    },
};

helper error => sub {
    my ($self, $status, $error) = @_;

    app->log->error( $error->{str} );

    no warnings 'experimental';
    my $template;
    given ($status) {
        $template = 'bad_request' when 400;
        $template = 'not_found'   when 404;
        $template = 'exception'   when 500;
        default { $template = 'unknown' }
    }

    $self->respond_to(
        json => { status => $status, json  => { error => $error || q{} } },
        html => { status => $status, error => $error->{str} || q{}, template => $template },
    );

    return;
};

helper meta_link => sub {
    my ( $self, $id ) = @_;

    my $meta = app->config->{sidebar}{meta};

    return $meta->{$id}{link} || $id;
};

helper meta_text => sub {
    my ( $self, $id ) = @_;

    my $meta = app->config->{sidebar}{meta};

    return $meta->{$id}{text};
};

helper get_gravatar => sub {
    my ( $self, $user, $size, %opts ) = @_;

    $opts{default} ||= app->config->{avatar_icon};
    $opts{email}   ||= $user->email;
    $opts{size}    ||= $size;

    my $url = Gravatar::URL::gravatar_url(%opts);

    return $url;
};

helper trim_clothes_code => sub {
    my ( $self, $clothes ) = @_;

    my $code = $clothes->code;
    $code =~ s/^0//;

    return $code;
};

helper order_clothes_price => sub {
    my ( $self, $order ) = @_;

    return 0 unless $order;

    my $price = 0;
    for ( $order->order_details ) {
        next unless $_->clothes;
        $price += $_->price;
    }

    return $price;
};

helper calc_overdue => sub {
    my ( $self, $order ) = @_;

    return 0 unless $order;

    my $target_dt = $order->target_date;
    my $return_dt = $order->return_date;

    return 0 unless $target_dt;

    $return_dt ||= DateTime->now( time_zone => app->config->{timezone} );

    my $DAY_AS_SECONDS = 60 * 60 * 24;

    my $epoch1 = $target_dt->epoch;
    my $epoch2 = $return_dt->epoch;

    my $dur = $epoch2 - $epoch1;
    return 0 if $dur < 0;
    return int($dur / $DAY_AS_SECONDS) + 1;
};

helper commify => sub {
    my $self = shift;
    local $_ = shift;
    1 while s/((?:\A|[^.0-9])[-+]?\d+)(\d{3})/$1,$2/s;
    return $_;
};

helper calc_late_fee => sub {
    my ( $self, $order ) = @_;

    my $price   = $self->order_clothes_price($order);
    my $overdue = $self->calc_overdue($order);
    return 0 unless $overdue;

    my $late_fee = $price * 0.2 * $overdue;

    return $late_fee;
};

helper flatten_user => sub {
    my ( $self, $user ) = @_;

    return unless $user;

    my %data = (
        $user->user_info->get_columns,
        $user->get_columns,
    );
    delete @data{qw/ user_id password /};

    return \%data;
};

helper tracking_url => sub {
    my ( $self, $order ) = @_;

    return unless $order;
    return unless $order->return_method;

    my ( $company, $id ) = split /,/, $order->return_method;
    return unless $id;

    my $driver;
    {
        no warnings 'experimental';

        given ($company) {
            $driver = 'KR::PostOffice' when /^우체국/;
            $driver = 'KR::CJKorea'    when m/^(대한통운|CJ|CJ\s*GLS|편의점)/i;
            $driver = 'KR::KGB'        when m/^KGB/i;
            $driver = 'KR::Hanjin'     when m/^한진/;
            $driver = 'KR::Yellowcap'  when m/^(KG\s*)?옐로우캡/i;
            $driver = 'KR::Dongbu'     when m/^(KG\s*)?동부/i;
        }
    }
    return unless $driver;

    my $tracking_url = Parcel::Track->new( $driver, $id )->uri;

    return $tracking_url;
};

helper order_price => sub {
    my ( $self, $order ) = @_;

    return unless $order;

    my $order_price       = 0;
    my %order_stage_price = (
        0 => 0,
        1 => 0, # 연장료 / 연장료 에누리
        2 => 0, # 배상비 / 배상비 에누리
        3 => 0, # 환불 수수료
    );
    for my $order_detail ( $order->order_details ) {
        $order_price                               += $order_detail->final_price;
        $order_stage_price{ $order_detail->stage } += $order_detail->final_price;
    }

    return ( $order_price, \%order_stage_price );
};

helper flatten_order => sub {
    my ( $self, $order ) = @_;

    return unless $order;

    my ( $order_price, $order_stage_price ) = $self->order_price($order);

    my %data = (
        $order->get_columns,
        status_name      => $order->status ? $order->status->name : q{},
        rental_date      => undef,
        target_date      => undef,
        user_target_date => undef,
        return_date      => undef,
        price            => $order_price,
        stage_price      => $order_stage_price,
        clothes_price    => $self->order_clothes_price($order),
        clothes          => [ $order->order_details({ clothes_code => { '!=' => undef } })->get_column('clothes_code')->all ],
        late_fee         => $self->calc_late_fee($order),
        overdue          => $self->calc_overdue($order),
        return_method    => $order->return_method || q{},
        tracking_url     => $self->tracking_url($order) || q{},
    );

    if ( $order->rental_date ) {
        $data{rental_date} = {
            raw => $order->rental_date,
            md  => $order->rental_date->month . '/' . $order->rental_date->day,
            ymd => $order->rental_date->ymd
        };
    }

    if ( $order->target_date ) {
        $data{target_date} = {
            raw => $order->target_date,
            md  => $order->target_date->month . '/' . $order->target_date->day,
            ymd => $order->target_date->ymd
        };
    }

    if ( $order->user_target_date ) {
        $data{user_target_date} = {
            raw => $order->user_target_date,
            md  => $order->user_target_date->month . '/' . $order->user_target_date->day,
            ymd => $order->user_target_date->ymd
        };
    }

    if ( $order->return_date ) {
        $data{return_date} = {
            raw => $order->return_date,
            md  => $order->return_date->month . '/' . $order->return_date->day,
            ymd => $order->return_date->ymd
        };
    }

    return \%data;
};

helper flatten_order_detail => sub {
    my ( $self, $order_detail ) = @_;

    return unless $order_detail;

    my %data = ( $order_detail->get_columns );

    return \%data;
};

helper flatten_clothes => sub {
    my ( $self, $clothes ) = @_;

    return unless $clothes;

    #
    # additional information for clothes
    #
    my %extra_data;
    # '대여중'인 항목만 주문서 정보를 포함합니다.
    my $order = $clothes->orders->find({ status_id => 2 });
    $extra_data{order} = $self->flatten_order($order) if $order;

    my @tags = $clothes->tags;;

    my %data = (
        $clothes->get_columns,
        %extra_data,
        status => $clothes->status->name,
        tags => [map { { $_->get_columns } } @tags],
    );

    return \%data;
};

helper flatten_booking => sub {
    my ( $self, $booking ) = @_;

    return unless $booking;

    my %data = $booking->get_columns;

    return \%data;
};

helper get_params => sub {
    my ( $self, @keys ) = @_;

    #
    # parameter can have multiple values
    #
    my @src_keys;
    my @dest_keys;
    my @values;
    for my $k (@keys) {
        my $v;
        if ( ref($k) eq 'ARRAY' ) {
            push @src_keys,  $k->[0];
            push @dest_keys, $k->[1];

            $v = $self->every_param( $k->[0] );
        }
        else {
            push @src_keys,  $k;
            push @dest_keys, $k;

            $v = $self->every_param($k);
        }

        if ($v) {
            if ( @$v == 1 ) {
                push @values, $v->[0];
            }
            elsif ( @$v < 1 ) {
                push @values, undef;
            }
            else {
                push @values, $v;
            }
        }
        else {
            push @values, undef;
        }
    }

    #
    # make parameter hash using explicit keys
    #
    my %params = zip @dest_keys, @values;

    #
    # remove not defined parameter key and values
    #
    defined $params{$_} ? 1 : delete $params{$_} for keys %params;

    return %params;
};

helper get_user => sub {
    my ( $self, $params ) = @_;

    #
    # validate params
    #
    my $v = $self->create_validator;
    $v->field('id')->required(1)->regexp(qr/^\d+$/);
    unless ( $self->validate( $v, $params ) ) {
        my @error_str;
        while ( my ( $k, $v ) = each %{ $v->errors } ) {
            push @error_str, "$k:$v";
        }
        return $self->error( 400, {
            str  => join(',', @error_str),
            data => $v->errors,
        });
    }

    #
    # find user
    #
    my $user = $DB->resultset('User')->find( $params );
    return $self->error( 404, {
        str  => 'user not found',
        data => {},
    }) unless $user;
    return $self->error( 404, {
        str  => 'user info not found',
        data => {},
    }) unless $user->user_info;

    return $user;
};

helper update_user => sub {
    my ( $self, $user_params, $user_info_params ) = @_;

    #
    # validate params
    #
    my $v = $self->create_validator;
    $v->field('id')->required(1)->regexp(qr/^\d+$/);
    $v->field('email')->email;
    $v->field('expires')->regexp(qr/^\d+$/);
    $v->field('phone')->regexp(qr/^\d+$/);
    $v->field('gender')->in(qw/ male female /);
    $v->field('birth')->regexp(qr/^(0|((19|20)\d{2}))$/);
    $v->field(qw/ height weight neck bust waist hip topbelly belly thigh arm leg knee foot pants /)->each(sub {
        shift->regexp(qr/^\d{1,3}$/);
    });
    $v->field('staff')->in( 0, 1 );
    unless ( $self->validate( $v, { %$user_params, %$user_info_params } ) ) {
        my @error_str;
        while ( my ( $k, $v ) = each %{ $v->errors } ) {
            push @error_str, "$k:$v";
        }
        return $self->error( 400, {
            str  => join(',', @error_str),
            data => $v->errors,
        });
    }

    #
    # find user
    #
    my $user = $DB->resultset('User')->find({ id => $user_params->{id} });
    return $self->error( 404, {
        str  => 'user not found',
        data => {},
    }) unless $user;
    return $self->error( 404, {
        str  => 'user info not found',
        data => {},
    }) unless $user->user_info;

    #
    # update user
    #
    {
        my $guard = $DB->txn_scope_guard;

        my %_user_params = %$user_params;
        delete $_user_params{id};

        if ( $_user_params{create_date} ) {
            $_user_params{create_date} = DateTime->from_epoch(
                epoch     => $_user_params{create_date},
                time_zone => app->config->{timezone},
            );
        }
        if ( $_user_params{update_date} ) {
            $_user_params{update_date} = DateTime->from_epoch(
                epoch     => $_user_params{update_date},
                time_zone => app->config->{timezone},
            );
        }

        $user->update( \%_user_params )
            or return $self->error( 500, {
                str  => 'failed to update a user',
                data => {},
            });

        $user->user_info->update({
            %$user_info_params,
            user_id => $user->id,
        }) or return $self->error( 500, {
            str  => 'failed to update a user info',
            data => {},
        });

        $guard->commit;

        #
        # event posting to opencloset/monitor
        #
        my $res = HTTP::Tiny->new(timeout => 1)->post_form(app->config->{monitor_uri} . '/events', {
            sender  => 'user',
            user_id => $user->id
        });

        $self->app->log->error("Failed to posting event: $res->{reason}") unless $res->{success};
    }

    return $user;
};

helper get_user_list => sub {
    my ( $self, $params ) = @_;

    #
    # validate params
    #
    my $v = $self->create_validator;
    $v->field('id')->regexp(qr/^\d+$/);
    unless ( $self->validate( $v, $params ) ) {
        my @error_str;
        while ( my ( $k, $v ) = each %{ $v->errors } ) {
            push @error_str, "$k:$v";
        }
        return $self->error( 400, {
            str  => join(',', @error_str),
            data => $v->errors,
        });
    }

    #
    # adjust params
    #
    $params->{id} = [ $params->{id} ]
        if defined $params->{id} && not ref $params->{id} eq 'ARRAY';

    #
    # find user
    #
    my $rs;
    if ( defined $params->{id} ) {
        $rs
            = $DB->resultset('User')
            ->search({ id => $params->{id} })
            ;
    }
    else {
        $rs = $DB->resultset('User');
    }
    return $self->error( 404, {
        str  => 'user list not found',
        data => {},
    }) if $rs->count == 0 && !$params->{allow_empty};

    return $rs;
};

helper create_order => sub {
    my ( $self, $order_params, $order_detail_params ) = @_;

    return unless $order_params;
    return unless ref($order_params) eq 'HASH';

    #
    # validate params
    #
    {
        my $v = $self->create_validator;
        $v->field('user_id')->required(1)->regexp(qr/^\d+$/)->callback(sub {
            my $val = shift;

            return 1 if $DB->resultset('User')->find({ id => $val });
            return ( 0, 'user not found using user_id' );
        });
        $v->field('additional_day')->regexp(qr/^\d+$/);
        $v->field(qw/ height weight neck bust waist hip topbelly belly thigh arm leg knee foot pants /)->each(sub {
            shift->regexp(qr/^\d{1,3}$/);
        });
        $v->field('bestfit')->in( 0, 1 );
        unless ( $self->validate( $v, $order_params ) ) {
            my @error_str;
            while ( my ( $k, $v ) = each %{ $v->errors } ) {
                push @error_str, "$k:$v";
            }
            $self->error( 400, {
                str  => join(',', @error_str),
                data => $v->errors,
            }), return;
        }
    }
    {
        my $v = $self->create_validator;
        $v->field('clothes_code')->regexp(qr/^[A-Z0-9]{4,5}$/)->callback(sub {
            my $val = shift;

            $val = sprintf( '%05s', $val ) if length $val == 4;

            return 1 if $DB->resultset('Clothes')->find({ code => $val });
            return ( 0, 'clothes not found using clothes_code' );
        });
        unless ( $self->validate( $v, $order_detail_params ) ) {
            my @error_str;
            while ( my ( $k, $v ) = each %{ $v->errors } ) {
                push @error_str, "$k:$v";
            }
            $self->error( 400, {
                str  => join(',', @error_str),
                data => $v->errors,
            }), return;
        }
    }

    #
    # adjust params
    #
    if ( $order_detail_params && $order_detail_params->{clothes_code} ) {
        $order_detail_params->{clothes_code} = [ $order_detail_params->{clothes_code} ]
            unless ref $order_detail_params->{clothes_code};

        for ( @{ $order_detail_params->{clothes_code} } ) {
            next unless length == 4;
            $_ = sprintf( '%05s', $_ );
        }
    }
    {
        #
        # override body measurement(size) from user's data
        #
        my $user = $self->get_user({ id => $order_params->{user_id} });
        #
        # we believe user is exist since parameter validator
        #
        for (qw/ height weight neck bust waist hip topbelly belly thigh arm leg knee foot pants /) {
            next if     defined $order_params->{$_};
            next unless defined $user->user_info->$_;

            app->log->debug( "overriding $_ from user for order creation" );
            $order_params->{$_} = $user->user_info->$_;
        }
    }

    #
    # TRANSACTION:
    #
    #   - create order
    #   - create order_detail
    #
    my ( $order, $error ) = do {
        my $guard = $DB->txn_scope_guard;
        try {
            #
            # create order
            #
            my $order = $DB->resultset('Order')->create( $order_params );
            die "failed to create a new order\n" unless $order;

            #
            # create order_detail
            #
            my ( $f_key ) = keys %$order_detail_params;
            return $order unless $f_key;
            unless ( ref $order_detail_params->{$f_key} ) {
                $order_detail_params->{$_} = [ $order_detail_params->{$_} ] for keys %$order_detail_params;
            }
            for ( my $i = 0; $i < @{ $order_detail_params->{$f_key} }; ++$i ) {
                my %params;
                for my $k ( keys %$order_detail_params ) {
                    $params{$k} = $order_detail_params->{$k}[$i];
                }

                if ( $params{clothes_code} ) {
                    if (   defined $params{name}
                        && defined $params{price}
                        && defined $params{final_price} )
                    {
                        $order->add_to_order_details( \%params )
                            or die "failed to create a new order_detail\n";
                    }
                    else {
                        my $clothes = $DB->resultset('Clothes')->find({ code => $params{clothes_code} });

                        my $name = $params{name} // join(
                            q{ - },
                            $self->trim_clothes_code($clothes),
                            app->config->{category}{ $clothes->category }{str},
                        );
                        my $price       = $params{price} // $clothes->price;
                        my $final_price = $params{final_price} // (
                            $clothes->price + $clothes->price * 0.2 * ($order_params->{additional_day} || 0)
                        );

                        $order->add_to_order_details({
                            %params,
                            clothes_code => $clothes->code,
                            name         => $name,
                            price        => $price,
                            final_price  => $final_price,
                        }) or die "failed to create a new order_detail\n";
                    }
                }
                else {
                    $order->add_to_order_details( \%params )
                        or die "failed to create a new order_detail\n";
                }
            }

            $order->add_to_order_details({
                name        => '배송비',
                price       => 0,
                final_price => 0,
            }) or die "failed to create a new order_detail for delivery_fee\n";
            $order->add_to_order_details({
                name        => '에누리',
                price       => 0,
                final_price => 0,
            }) or die "failed to create a new order_detail for discount\n";

            $guard->commit;

            return $order;
        }
        catch {
            chomp;
            app->log->error("failed to create a new order & a new order_clothes");
            app->log->error($_);

            return ( undef, $_ );
        };
    };

    #
    # response
    #
    $self->error( 500, {
        str  => $error,
        data => {},
    }), return unless $order;

    return $order;
};

helper get_order => sub {
    my ( $self, $params ) = @_;

    #
    # validate params
    #
    my $v = $self->create_validator;
    $v->field('id')->required(1)->regexp(qr/^\d+$/);
    unless ( $self->validate( $v, $params ) ) {
        my @error_str;
        while ( my ( $k, $v ) = each %{ $v->errors } ) {
            push @error_str, "$k:$v";
        }
        return $self->error( 400, {
            str  => join(',', @error_str),
            data => $v->errors,
        });
    }

    #
    # find order
    #
    my $order = $DB->resultset('Order')->find( $params );
    return $self->error( 404, {
        str  => 'order not found',
        data => {},
    }) unless $order;

    return $order;
};

helper update_order => sub {
    my ( $self, $order_params, $order_detail_params ) = @_;

    #
    # validate params
    #
    {
        my $v = $self->create_validator;
        $v->field('id')->required(1)->regexp(qr/^\d+$/);
        $v->field('user_id')->regexp(qr/^\d+$/)->callback(sub {
            my $val = shift;

            return 1 if $DB->resultset('User')->find({ id => $val });
            return ( 0, 'user not found using user_id' );
        });
        $v->field('additional_day')->regexp(qr/^\d+$/);
        $v->field(qw/ height weight neck bust waist hip topbelly belly thigh arm leg knee foot pants /)->each(sub {
            shift->regexp(qr/^\d{1,3}$/);
        });
        $v->field('bestfit')->in( 0, 1 );
        unless ( $self->validate( $v, $order_params ) ) {
            my @error_str;
            while ( my ( $k, $v ) = each %{ $v->errors } ) {
                push @error_str, "$k:$v";
            }
            $self->error( 400, {
                str  => join(',', @error_str),
                data => $v->errors,
            }), return;
        }
    }
    {
        my $v = $self->create_validator;
        $v->field('clothes_code')->regexp(qr/^[A-Z0-9]{4,5}$/)->callback(sub {
            my $val = shift;

            $val = sprintf( '%05s', $val ) if length $val == 4;

            return 1 if $DB->resultset('Clothes')->find({ code => $val });
            return ( 0, 'clothes not found using clothes_code' );
        });
        unless ( $self->validate( $v, $order_detail_params ) ) {
            my @error_str;
            while ( my ( $k, $v ) = each %{ $v->errors } ) {
                push @error_str, "$k:$v";
            }
            $self->error( 400, {
                str  => join(',', @error_str),
                data => $v->errors,
            }), return;
        }
    }

    #
    # adjust params
    #
    if ($order_detail_params) {
        for my $key (qw/
            id
            order_id
            clothes_code
            status_id
            name
            price
            final_price
            stage
            desc
        /)
        {
            if ( $order_detail_params->{$key} ) {
                $order_detail_params->{$key} = [ $order_detail_params->{$key} ]
                    unless ref $order_detail_params->{$key};

                if ( $key eq 'clothes_code' ) {
                    for ( @{ $order_detail_params->{$key} } ) {
                        next unless length == 4;
                        $_ = sprintf( '%05s', $_ );
                    }
                }
            }
        }
    }

    #
    # TRANSACTION:
    #
    #   - find   order
    #   - update order
    #   - update clothes status
    #   - update order_detail
    #
    my ( $order, $status, $error ) = do {
        my $guard = $DB->txn_scope_guard;
        try {
            #
            # find order
            #
            my $order = $DB->resultset('Order')->find({ id => $order_params->{id} });
            die "order not found\n" unless $order;
            my $from = $order->status_id;

            #
            # update order
            #
            {
                my %_params = %$order_params;
                delete $_params{id};
                $order->update( \%_params ) or die "failed to update the order\n";
            }

            #
            # update clothes status
            #
            if ( $order_params->{status_id} ) {
                for my $clothes ( $order->clothes ) {
                    $clothes->update({ status_id => $order_params->{status_id} })
                        or die "failed to update the clothes status\n";
                }
            }

            #
            # update order_detail
            #
            if ( $order_detail_params && $order_detail_params->{id} ) {
                my %_params = %$order_detail_params;
                for my $i ( 0 .. $#{ $_params{id} } ) {
                    my %p  = map { $_ => $_params{$_}[$i] } keys %_params;
                    my $id = delete $p{id};

                    my $order_detail = $DB->resultset('OrderDetail')->find({ id => $id });
                    die "order_detail not found\n" unless $order_detail;
                    $order_detail->update( \%p ) or die "failed to update the order_detail\n";
                }
            }

            $guard->commit;

            #
            # event posting to opencloset/monitor
            #
            my $to = $order_params->{status_id};
            return $order unless $to;
            return $order if     $to == $from;

            my $res = HTTP::Tiny->new(timeout => 1)->post_form(app->config->{monitor_uri} . '/events', {
                sender   => 'order',
                order_id => $order->id,
                from     => $from,
                to       => $to
            });

            $self->app->log->error("Failed to posting event: $res->{reason}") unless $res->{success};

            return $order;
        }
        catch {
            chomp;
            app->log->error("failed to update a new order & a new order_clothes");
            app->log->error($_);

            no warnings 'experimental';

            my $status;
            given ($_) {
                $status = 404 when 'order not found';
                default { $status = 500 }
            }

            return ( undef, $status, $_ );
        };
    };

    #
    # response
    #
    $self->error( $status, {
        str  => $error,
        data => {},
    }), return unless $order;

    return $order;
};

helper delete_order => sub {
    my ( $self, $params ) = @_;

    #
    # validate params
    #
    my $v = $self->create_validator;
    $v->field('id')->required(1)->regexp(qr/^\d+$/);
    unless ( $self->validate( $v, $params ) ) {
        my @error_str;
        while ( my ( $k, $v ) = each %{ $v->errors } ) {
            push @error_str, "$k:$v";
        }
        return $self->error( 400, {
            str  => join(',', @error_str),
            data => $v->errors,
        });
    }

    #
    # find order
    #
    my $order = $DB->resultset('Order')->find( $params );
    return $self->error( 404, {
        str  => 'order not found',
        data => {},
    }) unless $order;

    #
    # delete order
    #
    my $data = $self->flatten_order($order);
    $order->delete;

    return $data;
};

helper get_order_list => sub {
    my ( $self, $params ) = @_;

    #
    # validate params
    #
    my $v = $self->create_validator;
    $v->field('id')->regexp(qr/^\d+$/);
    unless ( $self->validate( $v, $params ) ) {
        my @error_str;
        while ( my ( $k, $v ) = each %{ $v->errors } ) {
            push @error_str, "$k:$v";
        }
        return $self->error( 400, {
            str  => join(',', @error_str),
            data => $v->errors,
        });
    }

    #
    # adjust params
    #
    $params->{id} = [ $params->{id} ]
        if defined $params->{id} && not ref $params->{id} eq 'ARRAY';

    #
    # find order
    #
    my $rs;
    if ( defined $params->{id} ) {
        $rs
            = $DB->resultset('Order')
            ->search({ id => $params->{id} })
            ;
    }
    else {
        $rs = $DB->resultset('Order');
    }
    return $self->error( 404, {
        str  => 'order list not found',
        data => {},
    }) if $rs->count == 0 && !$params->{allow_empty};

    return $rs;
};

helper create_order_detail => sub {
    my ( $self, $params ) = @_;

    return unless $params;
    return unless ref($params) eq 'HASH';

    #
    # validate params
    #
    my $v = $self->create_validator;
    $v->field('order_id')->required(1)->regexp(qr/^\d+$/)->callback(sub {
        my $val = shift;

        return 1 if $DB->resultset('Order')->find({ id => $val });
        return ( 0, 'order not found using order_id' );
    });
    $v->field('clothes_code')->regexp(qr/^[A-Z0-9]{4,5}$/)->callback(sub {
        my $val = shift;

        $val = sprintf( '%05s', $val ) if length $val == 4;

        return 1 if $DB->resultset('Clothes')->find({ code => $val });
        return ( 0, 'clothes not found using clothes_code' );
    });
    $v->field('status_id')->regexp(qr/^\d+$/)->callback(sub {
        my $val = shift;

        return 1 if $DB->resultset('Status')->find({ id => $val });
        return ( 0, 'status not found using status_id' );
    });
    $v->field(qw/ price final_price /)
        ->each( sub { shift->regexp(qr/^-?\d+$/) } );
    $v->field('stage')->regexp(qr/^\d+$/);

    unless ( $self->validate( $v, $params ) ) {
        my @error_str;
        while ( my ( $k, $v ) = each %{ $v->errors } ) {
            push @error_str, "$k:$v";
        }
        $self->error( 400, {
            str  => join(',', @error_str),
            data => $v->errors,
        }), return;
    }

    #
    # adjust params
    #
    $params->{clothes_code} = sprintf( '%05s', $params->{clothes_code} )
        if $params->{clothes_code} && length( $params->{clothes_code} ) == 4;

    my $order_detail = $DB->resultset('OrderDetail')->create($params);
    return $self->error( 500, {
        str  => 'failed to create a new order_detail',
        data => {},
    }) unless $order_detail;

    return $order_detail;
};

helper get_clothes => sub {
    my ( $self, $params ) = @_;

    #
    # validate params
    #
    my $v = $self->create_validator;
    $v->field('code')->required(1)->regexp(qr/^[A-Z0-9]{4,5}$/);
    unless ( $self->validate( $v, $params ) ) {
        my @error_str;
        while ( my ( $k, $v ) = each %{ $v->errors } ) {
            push @error_str, "$k:$v";
        }
        return $self->error( 400, {
            str  => join(',', @error_str),
            data => $v->errors,
        });
    }

    #
    # adjust params
    #
    $params->{code} = sprintf( '%05s', $params->{code} ) if length( $params->{code} ) == 4;

    #
    # find clothes
    #
    my $clothes = $DB->resultset('Clothes')->find( $params );
    return $self->error( 404, {
        str  => 'clothes not found',
        data => {},
    }) unless $clothes;

    return $clothes;
};

helper get_nearest_booked_order => sub {
    my ( $self, $user ) = @_;

    my $dt_now = DateTime->now( time_zone => app->config->{timezone} );
    my $dtf    = $DB->storage->datetime_parser;

    my $rs = $user->search_related(
        'orders',
        {
            'me.status_id' => 14, # 방문예약
            'booking.date' => { '>' => $dtf->format_datetime($dt_now) },
        },
        {
            join     => 'booking',
            order_by => [
                { -asc => 'booking.date' },
                { -asc => 'me.id'        },
            ],
        },
    );

    my $order = $rs->next;

    return $order;
};

helper convert_sec_to_locale => sub {
    my ( $self, $seconds ) = @_;

    my $dfd  = DateTime::Format::Duration->new( normalize => 'ISO', pattern => '%M:%S' );
    my $dur1 = DateTime::Duration->new( seconds => $seconds );
    my $dur2 = DateTime::Duration->new( $dfd->normalize($dur1) );
    my $dfhd = DateTime::Format::Human::Duration->new;

    my $locale = $dfhd->format_duration( $dur2, locale => "ko" );
    $locale =~ s/\s*(년|개월|주|일|시간|분|초|나노초)/$1/gms;
    $locale =~ s/\s+/ /gms;
    $locale =~ s/,//gms;

    return $locale;
};

helper convert_sec_to_hms => sub {
    my ( $self, $seconds ) = @_;

    my $dfd  = DateTime::Format::Duration->new( normalize => 'ISO', pattern => "%M:%S" );
    my $dur1 = DateTime::Duration->new( seconds => $seconds );
    my $hms  = sprintf(
        '%02d:%s',
        $seconds / 3600,
        $dfd->format_duration( DateTime::Duration->new( $dfd->normalize($dur1) ) ),
    );

    return $hms;
};

helper phone_format => sub {
    my ($self, $phone) = @_;
    return $phone if $phone !~ m/^[0-9]{10,11}$/;

    $phone =~ s/(\d{3})(\d{4})/$1-$2/;
    $phone =~ s/(\d{4})(\d{3,4})/$1-$2/;
    return $phone;
};

helper user_avg_diff => sub {
    my ( $self, $user ) = @_;

    my %data = (
        ret  => 0,
        diff => undef,
        avg  => undef,
    );
    for ( qw/ neck belly topbelly bust arm thigh waist hip leg foot knee / ) {
        $data{diff}{$_} = '-';
        $data{avg}{$_}  = 'N/A';
    }

    unless (
        $user->user_info->gender =~ m/^(male|female)$/
        && $user->user_info->height
        && $user->user_info->weight
    )
    {
        return \%data;
    }

    my $osg_db = OpenCloset::Size::Guess->new(
        'DB',
        _time_zone => app->config->{timezone},
        _schema    => $DB,
        _range     => 0,
    );
    $osg_db->gender( $user->user_info->gender );
    $osg_db->height( int $user->user_info->height );
    $osg_db->weight( int $user->user_info->weight );
    my $avg = $osg_db->guess;
    my $diff;
    for ( qw/ neck belly topbelly bust arm thigh waist hip leg foot knee / ) {
        $diff->{$_} = $user->user_info->$_ && $avg->{$_} ? sprintf( '%+.1f', $user->user_info->$_ - $avg->{$_} ) : '-';
        $avg->{$_}  = $avg->{$_} ? sprintf('%.1f', $avg->{$_}) : 'N/A';
    }

    %data = (
        ret  => 1,
        diff => $diff,
        avg  => $avg,
    );

    return \%data;
};

helper user_avg2 => sub {
    my ( $self, $user ) = @_;

    my %data = (
        ret  => 0,
        avg  => undef,
    );
    for ( qw/ bust waist topbelly belly thigh hip / ) {
        $data{avg}{$_}  = 'N/A';
    }

    unless (
        $user->user_info->gender =~ m/^(male|female)$/
        && $user->user_info->height
        && $user->user_info->weight
    )
    {
        return \%data;
    }

    my $height = $user->user_info->height;
    my $weight = $user->user_info->weight;
    my $gender = $user->user_info->gender;
    my $range  = 0;
    my %ret;
    do {
        my $dt_base = try {
            DateTime->new(
                time_zone => app->config->{timezone},
                year      => 2015,
                month     => 5,
                day       => 29,
            );
        };
        last unless $dt_base;

        my $dtf  = $DB->storage->datetime_parser;
        my $cond = {
            -or => [
                {
                    # 대여일이 2015-05-29 이전
                    -and => [
                        { 'booking.date' => { '<' => $dtf->format_datetime($dt_base) }, },
                        \[ "DATE_FORMAT(booking.date, '%H') < ?" => 19 ],
                    ],
                },
                {
                    # 대여일이 2015-05-29 이후
                    -and => [
                        { 'booking.date' => { '>=' => $dtf->format_datetime($dt_base) }, },
                        \[ "DATE_FORMAT(booking.date, '%H') < ?" => 22 ],
                    ],
                },
            ],
            'booking.gender' => $gender,
            'height' => { -between => [ $height - $range, $height + $range ] },
            'weight' => { -between => [ $weight - $range, $weight + $range ] },
        };
        my $attr = { join => [qw/ booking /] };

        my $avg2_range = 1;
        $cond->{belly}    = { -between => [ $user->user_info->belly    - $avg2_range, $user->user_info->belly    + $avg2_range ] } if $user->user_info->belly;
        $cond->{bust}     = { -between => [ $user->user_info->bust     - $avg2_range, $user->user_info->bust     + $avg2_range ] } if $user->user_info->bust;
        $cond->{hip}      = { -between => [ $user->user_info->hip      - $avg2_range, $user->user_info->hip      + $avg2_range ] } if $user->user_info->hip;
        $cond->{thigh}    = { -between => [ $user->user_info->thigh    - $avg2_range, $user->user_info->thigh    + $avg2_range ] } if $user->user_info->thigh;
        $cond->{topbelly} = { -between => [ $user->user_info->topbelly - $avg2_range, $user->user_info->topbelly + $avg2_range ] } if $user->user_info->topbelly;
        $cond->{waist}    = { -between => [ $user->user_info->waist    - $avg2_range, $user->user_info->waist    + $avg2_range ] } if $user->user_info->waist;

        my $order_rs = $DB->resultset('Order')->search( $cond, $attr );

        my %item = (
            belly    => [],
            bust     => [],
            hip      => [],
            thigh    => [],
            topbelly => [],
            waist    => [],
        );
        my %count = (
            total    => 0,
            belly    => 0,
            bust     => 0,
            hip      => 0,
            thigh    => 0,
            topbelly => 0,
            waist    => 0,
        );
        while ( my $order = $order_rs->next ) {
            ++$count{total};
            for (
                qw/
                belly
                bust
                hip
                thigh
                topbelly
                waist
                /
                )
            {
                next unless $order->$_; # remove undef & 0

                ++$count{$_};
                push @{ $item{$_} }, $order->$_;
            }
        }
        %ret = (
            height   => $height,
            weight   => $weight,
            gender   => $gender,
            count    => \%count,
            belly    => 0,
            bust     => 0,
            hip      => 0,
            thigh    => 0,
            topbelly => 0,
            waist    => 0,
        );
        $ret{belly}    = Statistics::Basic::mean( $item{belly} )->query;
        $ret{bust}     = Statistics::Basic::mean( $item{bust} )->query;
        $ret{hip}      = Statistics::Basic::mean( $item{hip} )->query;
        $ret{thigh}    = Statistics::Basic::mean( $item{thigh} )->query;
        $ret{topbelly} = Statistics::Basic::mean( $item{topbelly} )->query;
        $ret{waist}    = Statistics::Basic::mean( $item{waist} )->query;
    };
    return \%data unless %ret;

    my $avg = \%ret;
    for ( qw/ bust waist topbelly belly thigh hip / ) {
        $avg->{$_}  = $avg->{$_} ? sprintf('%.1f', $avg->{$_}) : 'N/A';
    }

    %data = (
        ret  => 1,
        avg  => $avg,
    );

    return \%data;
};

helper count_visitor => sub {
    my ( $self, $start_dt, $end_dt, $cb ) = @_;

    my $dtf        = $DB->storage->datetime_parser;
    my $booking_rs = $DB->resultset('Booking')->search(
        {
            date => {
                -between => [
                    $dtf->format_datetime($start_dt),
                    $dtf->format_datetime($end_dt),
                ],
            },
        },
        {
            prefetch       => {
                'orders' => {
                    'user' => 'user_info'
                }
            },
        },
    );

    my %count = (
        all        => { total => 0, male => 0, female => 0 },
        visited    => { total => 0, male => 0, female => 0 },
        notvisited => { total => 0, male => 0, female => 0 },
        bestfit    => { total => 0, male => 0, female => 0 },
        loanee     => { total => 0, male => 0, female => 0 },
    );
    while ( my $booking = $booking_rs->next ) {
        for my $order ( $booking->orders ) {
            next unless $order->user->user_info;

            my $gender = $order->user->user_info->gender;
            next unless $gender;

            ++$count{all}{total};
            ++$count{all}{$gender};

            if ( $order->rental_date ) {
                ++$count{loanee}{total};
                ++$count{loanee}{$gender};
            }

            if ( $order->bestfit ) {
                ++$count{bestfit}{total};
                ++$count{bestfit}{$gender};
            }

            use feature qw( switch );
            use experimental qw( smartmatch );
            given ( $order->status_id ) {
                when (/^12|14$/) {
                    ++$count{notvisited}{total};
                    ++$count{notvisited}{$gender};
                }
            }

            $cb->( $booking, $order, $gender ) if $cb && ref($cb) eq 'CODE';
        }
    }
    $count{visited}{total}  = $count{all}{total}  - $count{notvisited}{total};
    $count{visited}{male}   = $count{all}{male}   - $count{notvisited}{male};
    $count{visited}{female} = $count{all}{female} - $count{notvisited}{female};

    return \%count;
};

helper get_dbic_cond_attr_unpaid => sub {
    my $self = shift;

    #
    # SELECT
    #     o.id                    AS o_id,
    #     o.user_id               AS o_user_id,
    #     o.status_id             AS o_status_id,
    #     o.late_fee_pay_with     AS o_late_fee_pay_with,
    #     o.compensation_pay_with AS o_compensation_pay_with,
    #     SUM( od.final_price )   AS sum_final_price
    # FROM `order` AS o
    # LEFT JOIN `order_detail` AS od ON o.id = od.order_id
    # WHERE (
    #     o.`status_id` = 9
    #     AND (
    #         -- 연체료나 배상비 중 최소 하나는 미납이어야 함
    #         o.`late_fee_pay_with` = '미납'
    #         OR o.`compensation_pay_with` = '미납'
    #     )
    #     AND od.stage > 0
    # )
    # GROUP BY o.id
    # HAVING sum_final_price > 0
    # ;
    #

    my %cond = (
        -and => [
            'me.status_id'        => 9,
            'order_details.stage' => { '>' => 0 },
            -or => [
                'me.late_fee_pay_with'     => '미납',
                'me.compensation_pay_with' => '미납',
            ],
        ],
    );

    my %attr = (
        join      => [qw/ order_details /],
        group_by  => [qw/ me.id /],
        having    => { 'sum_final_price' => { '>' => 0 } },
        '+select' => [
            {
                sum => 'order_details.final_price',
                -as => 'sum_final_price'
            },
        ],
    );

    return ( \%cond, \%attr );
};

#
# API section
#
group {
    under '/api' => sub {
        my $self = shift;

        return 1 if $self->is_user_authenticated;

        my $req_path = $self->req->url->path;
        return 1 if $req_path =~ m{^/api/sms/validation(\.json)?$};
        return 1 if $req_path =~ m{^/api/postcode/search(\.json)?$};

        if ( $req_path =~ m{^/api/gui/booking-list(\.json)?$} ) {
            my $phone = $self->param('phone');
            my $sms   = $self->param('sms');

            $self->error( 400, { data => { error => 'missing phone' } } ), return unless defined $phone;
            $self->error( 400, { data => { error => 'missing sms'   } } ), return unless defined $sms;

            #
            # find user
            #
            my @users = $DB->resultset('User')->search(
                { 'user_info.phone' => $phone },
                { join => 'user_info' },
            );
            my $user = shift @users;
            $self->error( 400, { data => { error => 'user not found' } } ), return unless $user;

            #
            # GitHub #199 - check expires
            #
            my $now = DateTime->now( time_zone => app->config->{timezone} )->epoch;
            $self->error( 400, { data => { error => 'expiration is not set' } } ), return unless $user->expires;
            $self->error( 400, { data => { error => 'sms is expired'        } } ), return unless $user->expires > $now;
            $self->error( 400, { data => { error => 'sms is wrong'          } } ), return unless $user->check_password($sms);

            return 1;
        }
        elsif (
            $req_path =~ m{^/api/search/sms(\.json)?$}
            || $req_path =~ m{^/api/sms/\d+(\.json)?$}
        )
        {
            my $email    = $self->param('email');
            my $password = $self->param('password');

            $self->error( 400, { data => { error => 'missing email'     } } ), return unless defined $email;
            $self->error( 400, { data => { error => 'missing password'  } } ), return unless defined $password;
            $self->error( 400, { data => { error => 'password is wrong' } } ), return unless $self->authenticate($email, $password);

            return 1;
        }

        $self->error( 400, { data => { error => 'invalid_access' } } );
        return;
    };

    post '/sms'              => \&api_create_sms;
    post '/sms/validation'   => \&api_create_sms_validation;
    get  '/gui/booking-list' => \&api_gui_booking_list;
    any  '/postcode/search'  => \&api_postcode_search;

    sub api_create_sms {
        my $self = shift;

        #
        # fetch params
        #
        my %params = $self->get_params(qw/ to text status /);

        #
        # validate params
        #
        my $v = $self->create_validator;
        $v->field('to')->required(1)->regexp(qr/^#?\d+$/);
        $v->field('text')->required(1)->regexp(qr/^(\s|\S)+$/);
        $v->field('status')->in(qw/ pending sending sent /);

        unless ( $self->validate( $v, \%params ) ) {
            my @error_str;
            while ( my ( $k, $v ) = each %{ $v->errors } ) {
                push @error_str, "$k:$v";
            }
            $self->error( 400, {
                str  => join(',', @error_str),
                data => $v->errors,
            }), return;
        }

        $params{to} =~ s/-//g;
        my $from = app->config->{sms}{ app->config->{sms}{driver} }{_from};
        my $to   = $params{to};
        if ( $params{to} =~ m/^#(\d+)/ ) {
            my $order_id = $1;
            return $self->error( 404, {
                str  => 'failed to create a new sms: no order id',
                data => {},
            }) unless $order_id;

            my $order_obj = $DB->resultset('Order')->find($order_id);
            return $self->error( 404, {
                str  => 'failed to create a new sms: cannot get order object',
                data => {},
            }) unless $order_obj;

            my $phone = $order_obj->user->user_info->phone;
            return $self->error( 404, {
                str  => 'failed to create a new sms: cannot get order.user.user_info.phone',
                data => {},
            }) unless $phone;

            my $booking_time = $order_obj->booking->date->strftime('%H:%M');
            app->log->debug( "booking time: $booking_time" );
            if ( $booking_time eq '22:00' ) {
                $from = app->config->{sms}{from}{online};
            }
            $to = $phone;
        }
        my $sms = $DB->resultset('SMS')->create({
            %params,
            from => $from,
            to   => $to,
        });
        return $self->error( 404, {
            str  => 'failed to create a new sms',
            data => {},
        }) unless $sms;

        #
        # response
        #
        my %data = ( $sms->get_columns );

        $self->res->headers->header(
            'Location' => $self->url_for( '/api/sms/' . $sms->id ),
        );
        $self->respond_to( json => { status => 201, json => \%data } );
    }

    sub api_create_sms_validation {
        my $self = shift;

        #
        # fetch params
        #
        my %params = $self->get_params(qw/ name to /);

        #
        # validate params
        #
        my $v = $self->create_validator;
        $v->field('name')->required(1);
        $v->field('to')->required(1)->regexp(qr/^\d+$/);

        unless ( $self->validate( $v, \%params ) ) {
            my @error_str;
            while ( my ( $k, $v ) = each %{ $v->errors } ) {
                push @error_str, "$k:$v";
            }
            $self->error( 400, {
                str  => join(',', @error_str),
                data => $v->errors,
            }), return;
        }

        #
        # find user
        #
        my @users = $DB->resultset('User')->search(
            { 'user_info.phone' => $params{to} },
            { join => 'user_info' },
        );
        my $user = shift @users;

        if ($user) {
            #
            # fail if name and phone does not match
            #
            unless ( $user->name eq $params{name} ) {
                my $msg = sprintf(
                    'name and phone does not match: input(%s,%s), db(%s,%s)',
                    $params{name},
                    $params{to},
                    $user->name,
                    $user->user_info->phone,
                );
                app->log->warn($msg);

                $self->error( 400, {
                    str  => 'name and phone does not match',
                }), return;
            }
        }
        else {
            #
            # add user using one's name and phone if who does not exist
            #
            {
                my $guard = $DB->txn_scope_guard;

                my $_user = $DB->resultset('User')->create({ name => $params{name} });
                unless ($_user) {
                    app->log->warn('failed to create a user');
                    last;
                }

                my $_user_info = $DB->resultset('UserInfo')->create({
                    user_id => $_user->id,
                    phone   => $params{to},
                });
                unless ($_user_info) {
                    app->log->warn('failed to create a user_info');
                    last;
                }

                $guard->commit;

                $user = $_user;
            }

            app->log->info("create a user: name($params{name}), phone($params{to})");
        }

        #
        # fail if creating user is failed
        #
        unless ($user) {
            $self->error( 400, {
                str  => 'failed to create a user',
            }), return;
        }

        my $password = String::Random->new->randregex('\d\d\d\d\d\d');
        my $expires  = DateTime->now( time_zone => app->config->{timezone} )->add( minutes => 10 );
        $user->update({
            password => $password,
            expires  => $expires->epoch,
        }) or return $self->error( 500, {
            str  => 'failed to update a user',
            data => {},
        });
        app->log->debug( "sent temporary password: to($params{to}) password($password)" );

        my $sms = $DB->resultset('SMS')->create({
            to   => $params{to},
            from => app->config->{sms}{ app->config->{sms}{driver} }{_from},
            text => "열린옷장 인증번호: $password",
        });
        return $self->error( 404, {
            str  => 'failed to create a new sms',
            data => {},
        }) unless $sms;

        #
        # response
        #
        my %data = ( $sms->get_columns );

        $self->res->headers->header(
            'Location' => $self->url_for( '/api/sms/' . $sms->id ),
        );
        $self->respond_to( json => { status => 201, json => \%data } );
    }

    sub api_gui_booking_list {
        my $self = shift;

        #
        # fetch params
        #
        my %params = $self->get_params(qw/ gender /);

        #
        # validate params
        #
        my $v = $self->create_validator;
        $v->field('gender')->in(qw/ male female /);
        unless ( $self->validate( $v, \%params ) ) {
            my @error_str;
            while ( my ( $k, $v ) = each %{ $v->errors } ) {
                push @error_str, "$k:$v";
            }
            return $self->error( 400, {
                str  => join(',', @error_str),
                data => $v->errors,
            });
        }

        #
        # find booking
        #
        my $dt_start = DateTime->now( time_zone => app->config->{timezone} );
        unless ($dt_start) {
            my $msg = "cannot create start datetime object";
            app->log->warn($msg);
            $self->error( 500, {
                str  => $msg,
                data => {},
            });
            return;
        }

        my $dt_end = $dt_start->clone->truncate( to => 'day' )->add( hours => 24 * 15, seconds => -1 );
        unless ($dt_end) {
            my $msg = "cannot create end datetime object";
            app->log->warn($msg);
            $self->error( 500, {
                str  => $msg,
                data => {},
            });
            return;
        }

        my %search_attrs = (
            '+columns' => [
                { user_count => { count => 'user.id', -as => 'user_count' } },
            ],
            join       => { 'orders' => 'user' },
            group_by   => [ qw/ me.id / ],
            order_by   => { -asc => 'me.date' },
        );

        #
        # SELECT
        #     `me`.`id`,
        #     `me`.`date`,
        #     `me`.`gender`,
        #     `me`.`slot`,
        #     COUNT( `user`.`id` ) AS `user_count`
        # FROM `booking` `me`
        # LEFT JOIN `order` `orders`
        #     ON `orders`.`booking_id` = `me`.`id`
        # LEFT JOIN `user` `user`
        #     ON `user`.`id` = `orders`.`user_id`
        # WHERE (
        #     ( `me`.`date` BETWEEN ? AND ? )
        #     AND `me`.`gender` = ?
        #     AND `me`.`id` IS NOT NULL
        # )
        # GROUP BY `me`.`id` HAVING COUNT(user.id) < me.slot
        # ORDER BY `me`.`date` ASC
        #
        # http://stackoverflow.com/questions/5285448/mysql-select-only-not-null-values
        # https://metacpan.org/pod/DBIx::Class::Manual::Joining#Across-multiple-relations
        #
        my $dtf        = $DB->storage->datetime_parser;
        my $booking_rs = $DB->resultset('Booking')->search(
            {
                'me.id'     => { '!=' => undef },
                'me.gender' => $params{gender},
                'me.date'   => {
                    -between => [
                        $dtf->format_datetime($dt_start),
                        $dtf->format_datetime($dt_end),
                    ],
                },
            },
            \%search_attrs,
        );

        my @booking_list = $booking_rs->all;
        return $self->error( 404, {
            str  => 'booking list not found',
            data => {},
        }) unless @booking_list;

        #
        # additional information for clothes list
        #
        my @data;
        #
        # [GH 279] 직원 전용 방문 예약은 인원 제한과 상관없이 예약 가능하게 함
        # [GH 548] 방문 예약시 예약 마감된 시간을 표시할 수 있도록 수정
        #
        for my $b (@booking_list) {
            my $flat = $self->flatten_booking($b);

            unless (
                $self->is_user_authenticated
                && $self->current_user
                && $self->current_user->user_info
                && $self->current_user->user_info->staff
            )
            {
                next unless $flat->{slot} > 0;

                $flat->{id} = 0 unless $flat->{slot} > $flat->{user_count};
            }

            push @data, $flat;
        }

        #
        # response
        #
        $self->respond_to( json => { status => 200, json => \@data } );
    }

    sub api_postcode_search {
        my $self   = shift;
        my $q      = $self->param('q');
        my $p      = Postcodify->new( config => $ENV{MOJO_CONFIG} || './app.psgi.conf' );
        my $result = $p->search( $q );
        $self->app->log->info("postcode search query: $q");
        $self->render(text => decode_utf8($result->json), format => 'json');
    }

}; # end of API section

under '/' => sub {
    my $self = shift;

    {
        use experimental qw( smartmatch );

        my $req_path  = $self->req->url->path;
        my $site_type = app->config->{site_type};
        given ($site_type) {
            when ('all') {
                if ( $self->is_user_authenticated ) {
                    given ($req_path) {
                        when ('/visit') {
                            return 1;
                        }
                        when ('/login') {
                            $self->redirect_to( $self->url_for('/') );
                            return 1;
                        }
                        default {
                            return 1;
                        }
                    }
                }
                else {
                    given ($req_path) {
                        when ('/visit') {
                            return 1;
                        }
                        when (/(return|extension)(\/success\/?)?$/) {
                            return 1;
                        }
                        when ('/login') {
                            return 1;
                        }
                        default {
                            $self->redirect_to( $self->url_for('/visit') );
                            return;
                        }
                    }
                }
            }
            when ('staff') {
                if ( $self->is_user_authenticated ) {
                    given ($req_path) {
                        when ('/visit') {
                            app->log->warn( "/visit is not allowed by site_type config: $site_type" );
                            $self->redirect_to( $self->url_for('/') );
                            return;
                        }
                        when ('/login') {
                            $self->redirect_to( $self->url_for('/') );
                            return 1;
                        }
                        default {
                            return 1;
                        }
                    }
                }
                else {
                    given ($req_path) {
                        when ('/visit') {
                            app->log->warn( "/visit is not allowed by site_type config: $site_type" );
                            $self->redirect_to( $self->url_for('/login') );
                            return;
                        }
                        when (/(return|extension)(\/success\/?)?$/) {
                            return 1;
                        }
                        when ('/login') {
                            return 1;
                        }
                        default {
                            $self->redirect_to( $self->url_for('/login') );
                            return;
                        }
                    }
                }
            }
            when ('visit') {
                given ($req_path) {
                    when ('/visit') {
                        return 1;
                    }
                    default {
                        app->log->warn( "$req_path is not allowed by site_type config: $site_type" );
                        $self->redirect_to( $self->url_for('/visit') );
                        return;
                    }
                }
            }
            default {
                app->log->warn( "$req_path is not allowed by site_type config: $site_type" );
                return;
            }
        }
    }

    return;
};

get '/login';
post '/login' => sub {
    my $self = shift;

    my $username = $self->param('email');
    my $password = $self->param('password');
    my $remember = $self->param('remember');

    if ( $self->authenticate($username, $password) ) {
        $self->session->{expiration} = $remember ? $self->app->config->{expire}{remember} : $self->app->config->{expire}{default};

        my $remain   = $self->current_user->expires - DateTime->now( time_zone => app->config->{timezone} )->epoch;
        my $deadline = 60 * 60 * 24 * 7;
        my $uri      = q{/};

        if ( $remain < $deadline ) {
            $uri = '/user/' . $self->current_user->id;
            $self->flash(
                alert => {
                    type => 'warning',
                    msg  => '비밀번호 만료 시간이 얼마남지 않았습니다. 비밀번호를 변경해주세요.',
                },
            );
        }

        $self->redirect_to( $self->url_for($uri) );
    }
    else {
        $self->flash(error => 'Failed to Authentication');
        $self->redirect_to( $self->url_for('/login') );
    }
};

get '/logout' => sub {
    my $self = shift;

    $self->logout;
    $self->redirect_to( $self->url_for('/login') );
};

any '/visit' => sub {
    my $self = shift;

    my $type     = $self->param('type') || q{};
    my $name     = $self->param('name');
    my $phone    = $self->param('phone');
    my $service  = $self->param('service');
    my $privacy  = $self->param('privacy');
    my $password = $self->param('sms');

    my $email         = $self->param('email');
    my $gender        = $self->param('gender');
    my $address1      = $self->param('address1');
    my $address2      = $self->param('address2');
    my $address3      = $self->param('address3');
    my $address4      = $self->param('address4');
    my $birth         = $self->param('birth');
    my $order         = $self->param('order');
    my $booking       = $self->param('booking');
    my $booking_saved = $self->param('booking-saved');
    my $wearon_date   = $self->param('wearon_date');
    my $purpose       = $self->param('purpose');
    my $purpose2      = $self->param('purpose2');
    my $pre_category  = $self->param('pre_category');
    my $pre_color     = $self->param('pre_color');

    app->log->debug("type: $type");
    app->log->debug("name: $name");
    app->log->debug("phone: $phone");
    app->log->debug("service: $service");
    app->log->debug("privacy: $privacy");
    app->log->debug("sms: $password");

    app->log->debug("email: $email");
    app->log->debug("gender: $gender");
    app->log->debug("address1: $address1");
    app->log->debug("address2: $address2");
    app->log->debug("address3: $address3");
    app->log->debug("address4: $address4");
    app->log->debug("birth: $birth");
    app->log->debug("order: $order");
    app->log->debug("booking: $booking");
    app->log->debug("booking-saved: $booking_saved");
    app->log->debug("wearon_date: $wearon_date");
    app->log->debug("purpose: $purpose");
    app->log->debug("purpose2: $purpose2");
    app->log->debug("pre_category: $pre_category");
    app->log->debug("pre_color: $pre_color");

    #
    # find user
    #
    my @users = $DB->resultset('User')->search(
        {
            'me.name'         => $name,
            'user_info.phone' => $phone,
        },
        { join => 'user_info' },
    );
    my $user = shift @users;
    unless ($user) {
        app->log->warn( 'user not found' );
        return;
    }
    unless ($user->user_info) {
        app->log->warn( 'user_info not found' );
        return;
    }

    #
    # validate code
    #
    my $now = DateTime->now( time_zone => app->config->{timezone} )->epoch;
    unless ( $user->expires && $user->expires > $now ) {
        app->log->warn( $user->email . "\'s password is expired" );
        $self->stash( alert => '인증코드가 만료되었습니다.' );
        return;
    }
    unless ( $user->check_password($password) ) {
        app->log->warn( $user->email . "\'s password is wrong" );
        $self->stash( alert => '인증코드가 유효하지 않습니다.' );
        return;
    }

    $self->stash( order => $self->get_nearest_booked_order($user) );
    if ( $type eq 'visit' ) {
        #
        # GH #253
        #
        #   사용자가 동일 시간대 중복 방문 예약할 수 있는 경우를 방지하기 위해
        #   예약 관련 신청/변경/취소 요청이 들어오면 인증 번호를 검증한 후
        #   강제로 만료시킵니다.
        #
        $user->update({ expires  => $now });

        #
        # 예약 신청/변경/취소
        #

        my %user_params;
        my %user_info_params;

        $user_params{id}                = $user->id;
        $user_params{email}             = $email        if $email         && $email        ne $user->email;
        $user_info_params{gender}       = $gender       if $gender        && $gender       ne $user->user_info->gender;
        $user_info_params{address1}     = $address1     if $address1      && $address1     ne $user->user_info->address1;
        $user_info_params{address2}     = $address2     if $address2      && $address2     ne $user->user_info->address2;
        $user_info_params{address3}     = $address3     if $address3      && $address3     ne $user->user_info->address3;
        $user_info_params{address4}     = $address4     if $address4      && $address4     ne $user->user_info->address4;
        $user_info_params{birth}        = $birth        if $birth         && $birth        ne $user->user_info->birth;
        $user_info_params{wearon_date}  = $wearon_date  if $wearon_date   && $wearon_date  ne $user->user_info->wearon_date;
        $user_info_params{purpose}      = $purpose      if $purpose       && $purpose      ne $user->user_info->purpose;
        $user_info_params{purpose2}     = $purpose2 || q{};
        $user_info_params{pre_category} = $pre_category if $pre_category  && $pre_category ne $user->user_info->pre_category;
        $user_info_params{pre_color}    = $pre_color    if $pre_color     && $pre_color    ne $user->user_info->pre_color;

        #
        # tune pre_category
        #
        if ( $user_info_params{pre_category} ) {
            my $items_str = $user_info_params{pre_category};
            my @items     = grep { $_ } map { s/^\s+|\s+$//g; $_ } split /,/, $items_str;
            $user_info_params{pre_category} = join q{,}, @items;
        }

        #
        # tune pre_color
        #
        if ( $user_info_params{pre_color} ) {
            my $items_str = $user_info_params{pre_color};
            my @items     = grep { $_ } map { s/^\s+|\s+$//g; $_ } split /,/, $items_str;
            $user_info_params{pre_color} = join q{,}, @items;
        }

        if ( $booking == -1 ) {
            #
            # 예약 취소
            #
            my $order_obj = $DB->resultset('Order')->find($order);
            if ($order_obj) {
                my $msg = sprintf(
                    "%s님 %s 방문 예약이 취소되었습니다.",
                    $user->name,
                    $order_obj->booking->date->strftime('%m월 %d일 %H시 %M분'),
                );
                $DB->resultset('SMS')->create({
                    to   => $user->user_info->phone,
                    from => app->config->{sms}{ app->config->{sms}{driver} }{_from},
                    text => $msg,
                }) or app->log->warn("failed to create a new sms: $msg");

                $order_obj->delete;
            }
        }
        else {
            $user = $self->update_user( \%user_params, \%user_info_params );
            if ($user) {
                if ($booking_saved) {
                    #
                    # 이미 예약 정보가 저장되어 있는 경우 - 예약 변경 상황
                    #
                    my $order_obj = $DB->resultset('Order')->find($order);
                    if ($order_obj) {
                        if ( $booking != $booking_saved ) {
                            #
                            # 변경한 예약 정보가 기존 정보와 다를 경우 갱신함
                            #
                            $order_obj->update({ booking_id => $booking });
                        }

                        my $msg = sprintf(
                            "%s님 %s으로 방문 예약이 변경되었습니다.",
                            $user->name,
                            $order_obj->booking->date->strftime('%m월 %d일 %H시 %M분'),
                        );
                        $DB->resultset('SMS')->create({
                            to   => $user->user_info->phone,
                            from => app->config->{sms}{ app->config->{sms}{driver} }{_from},
                            text => $msg,
                        }) or app->log->warn("failed to create a new sms: $msg");
                    }
                }
                else {
                    #
                    # 예약 정보가 없는 경우 - 신규 예약 신청 상황
                    #
                    my $order_obj = $user->create_related('orders', {
                        status_id  => 14,      # 방문예약: status 테이블 참조
                        booking_id => $booking,
                    });
                    if ($order_obj) {
                        my $msg = sprintf(
                            qq{%s님 %s으로 방문 예약이 완료되었습니다.
<열린옷장 위치안내>
서울특별시 광진구 아차산로 213 국민은행 건대입구역 1번 출구로 나오신 뒤 오른쪽으로 꺾어 100M 가량 직진하시면 1층에 국민은행이 있는 건물 5층으로 올라오시면 됩니다. (도보로 2~3분 소요)
네이버 지도 안내: http://me2.do/xMi9nmgc},
                            $user->name,
                            $order_obj->booking->date->strftime('%m월 %d일 %H시 %M분'),
                        );
                        $DB->resultset('SMS')->create({
                            to   => $user->user_info->phone,
                            from => app->config->{sms}{ app->config->{sms}{driver} }{_from},
                            text => $msg,
                        }) or app->log->warn("failed to create a new sms: $msg");
                    }
                }
            }
            else {
                my $error_msg = "유효하지 않은 정보입니다: " . $self->stash('error');
                app->log->warn($error_msg);
                $self->stash( alert => $error_msg );
            }
        }
    }

    $self->stash(
        load     => app->config->{visit_load},
        type     => $type,
        user     => $user,
        password => $password,
    );
};

get '/order' => sub {
    my $self = shift;

    #
    # fetch params
    #
    my %params        = $self->get_params(qw/ id /);
    my %search_params = $self->get_params(qw/ booking_ymd status /);

    my $p = $self->param('p') || 1;
    my $s = $self->param('s') || app->config->{entries_per_page};

    my $rs = $self->get_order_list({
        %params,
        allow_empty => 1,
    });

    #
    # undef       => '상태없음'
    # late        => '연장중'
    # rental-late => '대여중(연장아님)'
    # unpaid      => '미납'
    #
    # 1     =>  '대여가능'
    # 2     =>  '대여중'
    # 3     =>  '대여불가'
    # 4     =>  '예약'
    # 5     =>  '세탁'
    # 6     =>  '수선'
    # 7     =>  '분실'
    # 8     =>  '폐기'
    # 9     =>  '반납'
    # 10    =>  '부분반납'
    # 11    =>  '반납배송중'
    # 12    =>  '방문안함'
    # 13    =>  '방문'
    # 14    =>  '방문예약'
    # 15    =>  '배송예약'
    # 16    =>  '치수측정'
    # 17    =>  '의류준비'
    # 18    =>  '포장'
    # 44    =>  '포장완료'
    # 19    =>  '결제대기'
    # 20    =>  '탈의01'
    # 21    =>  '탈의02'
    # 22    =>  '탈의03'
    # 23    =>  '탈의04'
    # 24    =>  '탈의05'
    # 25    =>  '탈의06'
    # 26    =>  '탈의07'
    # 27    =>  '탈의08'
    # 28    =>  '탈의09'
    # 29    =>  '탈의10'
    # 30    =>  '탈의11'
    # 31    =>  '탈의12'
    # 32    =>  '탈의13'
    # 33    =>  '탈의14'
    # 34    =>  '탈의15'
    # 35    =>  '탈의16'
    # 36    =>  '탈의17'
    # 37    =>  '탈의18'
    # 38    =>  '탈의19'
    # 39    =>  '탈의20'
    # 40    =>  '대여안함'
    # 41    =>  '포장취소'
    # 42    =>  '환불'
    # 43    =>  '사이즈없음'
    #

    {
        no warnings 'experimental';
        my $status_id  = $search_params{status};
        my $dt_day_end = DateTime->today( time_zone => app->config->{timezone} )->add( hours => 24, seconds => -1 );
        my $dtf        = $DB->storage->datetime_parser;
        my %cond;
        my %attr;
        given ($status_id) {
            when ('undef') {
                %cond = ( status_id => { '=' => undef },);
            }
            when ('late') {
                %cond = (
                    -and => [
                        status_id   => 2,
                        target_date => { '<' => $dtf->format_datetime($dt_day_end) },
                    ],
                );
            }
            when ('rental-late') {
                %cond = (
                    -and => [
                        status_id   => 2,
                        target_date => { '>=' => $dtf->format_datetime($dt_day_end) },
                    ],
                );
            }
            when ('unpaid') {
                my ( $cond_ref, $attr_ref ) = $self->get_dbic_cond_attr_unpaid;

                %cond = %$cond_ref;
                %attr = (
                    %$attr_ref,
                    order_by => 'target_date',
                );
            }
            default {
                my @valid = 1 .. 44;
                %cond = ( status_id => $status_id ) if $status_id ~~ @valid;
            }
        }
        $rs = $rs->search( \%cond, \%attr );
    }

    {
        my $status_id   = $search_params{status} || '';
        my $dt_today    = DateTime->now( time_zone => app->config->{timezone} );
        my $booking_ymd = $search_params{booking_ymd} || $dt_today->ymd;
        last unless $booking_ymd;

        unless ( $booking_ymd =~ m/^(\d{4})-(\d{2})-(\d{2})$/ ) {
            app->log->warn( "invalid booking_ymd format: $booking_ymd" );
            last;
        }

        my $dt_start = try {
            DateTime->new(
                time_zone => app->config->{timezone},
                year      => $1,
                month     => $2,
                day       => $3,
            );
        };
        unless ($dt_start) {
            app->log->warn( "cannot create start datetime object using booking_ymd" );
            last;
        }

        my $dt_end = $dt_start->clone->add( hours => 24, seconds => -1 );
        unless ($dt_end) {
            app->log->warn( "cannot create end datetime object using booking_ymd" );
            last;
        }

        my $dtf = $DB->storage->datetime_parser;
        ## 포장완료, #647
        my @order_by =
            $status_id =~ /^44$/
            ? ( { -asc => 'booking.date' }, { -desc => 'update_date' } )
            : ( { -asc => 'update_date' }, { -asc => 'booking.date' } );
        $rs = $rs->search(
            {
                'booking.date' => {
                    -between => [
                        $dtf->format_datetime($dt_start),
                        $dtf->format_datetime($dt_end),
                    ],
                },
            },
            {
                join     => [qw/ booking /],
                order_by => [@order_by],
            },
        );
    }

    $rs = $rs->search( undef, { page => $p, rows => $s } );
    my $pageset = Data::Pageset->new({
        total_entries    => $rs->pager->total_entries,
        entries_per_page => $rs->pager->entries_per_page,
        pages_per_set    => 5,
        current_page     => $p,
    });

    #
    # response
    #
    $self->stash(
        order_list    => $rs,
        pageset       => $pageset,
        search_status => $search_params{status} || q{},
    );

    $self->respond_to( html => { status => 200 } );
} => 'order';

post '/order' => sub {
    my $self = shift;

    #
    # fetch params
    #
    my %order_params        = $self->get_params(qw/ id /);
    my %order_detail_params = $self->get_params(qw/ clothes_code /);

    #
    # adjust params
    #
    if ( $order_detail_params{clothes_code} ) {
        $order_detail_params{clothes_code} = [ $order_detail_params{clothes_code} ]
            unless ref $order_detail_params{clothes_code};

        for ( @{ $order_detail_params{clothes_code} } ) {
            next unless length == 4;
            $_ = sprintf( '%05s', $_ );
        }
    }

    my ( $order, $error ) = do {
        my $guard = $DB->txn_scope_guard;
        try {
            use experimental qw( smartmatch );

            #
            # find order
            #
            my $order = $DB->resultset('Order')->find( $order_params{id} );
            die "order not found: $order_params{id}\n" unless $order;

            my @invalid = (
                2,  # 대여중
                9,  # 반납
                10, # 부분반납
                11, # 반납배송중
                12, # 방문안함
                19, # 결제대기
                40, # 대여안함
                42, # 환불
                43, # 사이즈없음
            );
            my $status_id = $order->status_id;
            if ( $status_id ~~ @invalid ) {
                my $status = $DB->resultset('Status')->find( $status_id )->name;
                die "이미 $status 인 주문서 입니다.\n";
            }

            #
            # 주문서를 포장완료(44) 상태로 변경
            #
            $order->update({ status_id => 44 });
            my $res = HTTP::Tiny->new(timeout => 1)->post_form(app->config->{monitor_uri} . '/events', {
                sender   => 'order',
                order_id => $order_params{id},
                from     => 18,
                to       => 44
            });

            $self->app->log->error("Failed to posting event: $res->{reason}") unless $res->{success};

            for ( my $i = 0; $i < @{ $order_detail_params{clothes_code} }; ++$i ) {
                my $clothes_code = $order_detail_params{clothes_code}[$i];
                my $clothes      = $DB->resultset('Clothes')->find({ code => $clothes_code });

                die "clothes not found: $clothes_code\n" unless $clothes;

                my $name = join(
                    q{ - },
                    $self->trim_clothes_code($clothes),
                    app->config->{category}{ $clothes->category }{str},
                );

                #
                # 주문서 하부의 모든 의류 항목을 결제대기(19) 상태로 변경
                #
                $clothes->update({ status_id => 19 });

                $order->add_to_order_details({
                    clothes_code => $clothes->code,
                    status_id    => 19, # 주문서 하부의 모든 의류 항목을 결제대기(19) 상태로 변경
                    name         => $name,
                    price        => $clothes->price,
                    final_price  => $clothes->price,
                }) or die "failed to create a new order_detail\n";
            }

            $order->add_to_order_details({
                name        => '배송비',
                price       => 0,
                final_price => 0,
            }) or die "failed to create a new order_detail for delivery_fee\n";
            $order->add_to_order_details({
                name        => '에누리',
                price       => 0,
                final_price => 0,
            }) or die "failed to create a new order_detail for discount\n";

            $guard->commit;

            return $order;
        }
        catch {
            chomp;
            app->log->error("failed to update the order & create a new order_detail");
            app->log->error($_);
            return ( undef, $_ );
        }
    };
    return $self->error(500, {str => $error}) unless $order;

    #
    # response
    #
    $self->redirect_to('/rental');
};

get '/order/:id' => sub {
    my $self = shift;

    #
    # fetch params
    #
    my %params = $self->get_params(qw/ id /);

    my $order = $self->get_order( \%params );
    return unless $order;

    #
    # 결제 대기 상태이면 사용자의 정보를 주문서에 동기화 시킴
    #
    if ( $order->status_id == 19 ) {
        my $user    = $order->user;
        my $comment = $user->user_info->comment ? $user->user_info->comment . "\n" : q{};
        my $desc    = $order->desc              ? $order->desc              . "\n" : q{};
        $order->update({
            wearon_date  => $user->user_info->wearon_date,
            purpose      => $user->user_info->purpose,
            purpose2     => $user->user_info->purpose2,
            pre_category => $user->user_info->pre_category,
            pre_color    => $user->user_info->pre_color,
            height       => $user->user_info->height,
            weight       => $user->user_info->weight,
            neck         => $user->user_info->neck,
            bust         => $user->user_info->bust,
            waist        => $user->user_info->waist,
            hip          => $user->user_info->hip,
            topbelly     => $user->user_info->topbelly,
            belly        => $user->user_info->belly,
            thigh        => $user->user_info->thigh,
            arm          => $user->user_info->arm,
            leg          => $user->user_info->leg,
            knee         => $user->user_info->knee,
            foot         => $user->user_info->foot,
            pants        => $user->user_info->pants,
            desc         => $comment . $desc,
        });
    }

    my $history;
    my $orders = $order->user->orders;
    while ( my $order = $orders->next ) {
        my $late_fee_pay_with     = $order->late_fee_pay_with;
        my $compensation_pay_with = $order->compensation_pay_with;

        if ( $late_fee_pay_with && $late_fee_pay_with =~ /(미납|불납|부분완납)/ ) {
            $history = $1;
            last;
        }

        if ( $compensation_pay_with && $compensation_pay_with =~ /(미납|불납|부분완납)/ ) {
            $history = $1;
            last;
        }
    }

    #
    # response
    #
    $self->render(
        'order-id',
        order   => $order,
        history => $history,
    );
};

post '/order/:id/update' => sub {
    my $self = shift;

    #
    # fetch params
    #
    my %search_params = $self->get_params(qw/ id /);
    my %update_params = $self->get_params(qw/ name value pk /);

    my $order = $self->get_order( \%search_params );
    return unless $order;

    my @status_objs = $DB->resultset('Status')->all;
    my %status;
    $status{$_->id} = $_->name for @status_objs;

    my $name  = $update_params{name};
    my $value = $update_params{value};
    my $pk    = $update_params{pk};
    app->log->info( "order update: $name.$value" );

    #
    # update column
    #
    if ( $name =~ s/^detail-// ) {
        my $detail = $order->order_details({ id => $pk })->next;
        if ($detail) {
            unless ( $detail->$name eq $value ) {
                app->log->info(
                    sprintf(
                        "  order_detail.$name %d [%s] -> [%s]",
                        $detail->id,
                        $detail->$name // 'N/A',
                        $value         // 'N/A',
                    ),
                );
                $detail->update({ $name => $value });
            }
        }
    }
    else {
        if ( $name eq 'status_id' ) {
            my $guard = $DB->txn_scope_guard;
            try {
                unless ( $order->status_id == $value ) {
                    #
                    # update order.status_id
                    #
                    app->log->info(
                        sprintf(
                            "  order.status: %d [%s] -> [%s]",
                            $order->id,
                            $order->status->name // 'N/A',
                            $status{$value}      // 'N/A',
                        ),
                    );
                    $order->update({ $name => $value });

                    #
                    # GH #614
                    #
                    #   주문확정일때에 SMS 를 전송
                    #   주문서의 상태가 -> 대여중
                    #
                    if ( $value == 2 ) {
                        my $from = app->config->{sms}{ app->config->{sms}{driver} }{_from};
                        my $to   = $order->user->user_info->phone;
                        my $msg = $self->render_to_string(
                            "sms/order-confirmed", format => 'txt',
                            order => $order
                        );

                        my $sms = $DB->resultset('SMS')->create(
                            {
                                to   => $to,
                                from => $from,
                                text => $msg
                            }
                        );

                        $self->app->log->error("Failed to create a new SMS: $msg") unless $sms;
                    }
                }

                #
                # update clothes.status_id
                #
                for my $clothes ( $order->clothes ) {
                    unless ( $clothes->status_id == $value ) {
                        app->log->info(
                            sprintf(
                                "  clothes.status: [%s] [%s] -> [%s]",
                                $clothes->code,
                                $clothes->status->name // 'N/A',
                                $status{ $value }      // 'N/A',
                            ),
                        );
                        $clothes->update({ $name => $value });
                    }
                }

                #
                # update order_detail.status_id
                #
                for my $order_detail ( $order->order_details ) {
                    next unless $order_detail->clothes;

                    unless ( $order_detail->status_id == $value ) {
                        app->log->info(
                            sprintf(
                                "  order_detail.status: %d [%s] -> [%s]",
                                $order_detail->id,
                                $order_detail->status->name // 'N/A',
                                $status{$value}             // 'N/A',
                            ),
                        );
                        $order_detail->update({ $name => $value });
                    }
                }

                $guard->commit;
            }
            catch {
                app->log->error("failed to update status of the order & clothes");
                app->log->error($_);
            };
        }
        else {
            unless ( $order->$name eq $value ) {
                app->log->info(
                    sprintf(
                        "  order.$name: %d %s -> %s",
                        $order->id,
                        $order->$name // 'N/A',
                        $value        // 'N/A',
                    ),
                );
                $order->update({ $name => $value });
            }
        }
    }

    #
    # response
    #
    $self->respond_to({ data => q{} });
};

get '/sms' => sub {
    my $self = shift;

    my %params = $self->get_params(qw/ to msg /);

    my $sender = SMS::Send->new(
        app->config->{sms}{driver},
        %{ app->config->{sms}{ app->config->{sms}{driver} } },
    );
    app->log->debug( sprintf('sms.driver: [%s]', app->config->{sms}{driver}) );

    my $balance = +{ success => undef };
    $balance = $sender->balance if $sender->_OBJECT_->can('balance');

    $self->stash(
        to      => $params{to}  || q{},
        msg     => $params{msg} || q{},
        balance => $balance->{success} ? $balance->{detail} : { cash => 0, point => 0 },
    );
};

get '/donation' => sub {
    my $self = shift;

    #
    # fetch params
    #
    my $p = $self->param('p') || 1;
    my $s = $self->param('s') || app->config->{entries_per_page};
    my $q = $self->param('q');

    my $cond;
    my $join = [ { 'user' => 'user_info' } ];
    if ($q) {
        $cond = [
            { 'name'               => { like => "%$q%" } },
            { 'email'              => { like => "%$q%" } },
            { 'user_info.phone'    => { like => "%$q%" } },
            { 'user_info.address4' => { like => "%$q%" } }, # 상세주소만 검색
            { 'user_info.birth'    => { like => "%$q%" } },
            { 'user_info.gender'   => $q },
        ];

        if ( $q =~ m/^\w{4,5}$/ ) {
            push @$cond, { 'clothes.code' => sprintf( '%05s', uc($q) ) };
            $join = [ 'clothes', { 'user' => 'user_info' } ];
        }
    }
    else {
        $cond = {};
    }

    my $rs = $DB->resultset('Donation')->search(
        $cond,
        {
            join     => $join,
            order_by => { -asc => 'id' },
            page     => $p,
            rows     => $s
        },
    );

    my $bucket = $DB->resultset('Clothes')->search({
        donation_id => undef
    });

    my $pageset = Data::Pageset->new({
        total_entries    => $rs->pager->total_entries,
        entries_per_page => $rs->pager->entries_per_page,
        pages_per_set    => 5,
        current_page     => $p,
    });

    $self->stash(
        donation_list => $rs,
        bucket        => $bucket,
        pageset       => $pageset,
        q             => $q || q{},
    );
};

get '/stat/bestfit' => sub {
    my $self = shift;

    my $rs = $DB->resultset('Order')->search(
        { bestfit => 1 },
        {
            order_by => [
                { -asc => 'order_details.clothes_code' },
            ],
            prefetch => {
                'order_details' => {
                    'clothes' => {
                        'donation' => 'user',
                    },
                },
            },
        },
    );

    $self->stash( order_rs => $rs,);
} => 'stat-bestfit';

get '/stat/clothes/amount' => sub {
    my $self = shift;

    my $rs = $DB->resultset('Clothes')->search(
        undef,
        {
            columns  => [qw/ category /],
            group_by => 'category'
        }
    );

    my @available_status_ids = (
        1, # 대여가능
        2, # 대여중
        5, # 세탁
        6, # 수선
        9, # 반납
    );

    my @amount;
    while (my $clothes = $rs->next) {
        my $category = $clothes->category;

        my $m_quantity = $DB->resultset('Clothes')->search(
            {
                category  => $category,
                gender    => 'male',
                status_id => \@available_status_ids,
            },
        );
        my $f_quantity = $DB->resultset('Clothes')->search(
            {
                category  => $category,
                gender    => 'female',
                status_id => \@available_status_ids,
            },
        );

        my $m_rental = $DB->resultset('Clothes')->search(
            {
                category  => $category,
                gender    => 'male',
                status_id => 2, # 대여중
            }
        );
        my $f_rental = $DB->resultset('Clothes')->search(
            {
                category  => $category,
                gender    => 'female',
                status_id => 2, # 대여중
            }
        );

        push(
            @amount,
            {
                category => $category,
                quantity => $m_quantity + $f_quantity,
                rental   => $m_rental + $f_rental,
                male     => {
                    quantity => $m_quantity,
                    rental   => $m_rental,
                },
                female => {
                    quantity => $f_quantity,
                    rental   => $f_rental,
                },
            }
        );
    }

    $self->stash( amount => \@amount );
} => 'stat-clothes-amount';

get '/stat/clothes/amount/category/:category/gender/:gender' => sub {
    my $self = shift;

    my %criterion_of = (
        belt      => 'length',
        blouse    => 'bust',
        coat      => 'topbelly',
        jacket    => 'topbelly',
        onepiece  => 'topbelly',
        pants     => 'waist',
        shirt     => 'bust',
        shoes     => 'length',
        skirt     => 'hip',
        tie       => 'color',
        waistcoat => 'bust',
    );

    my @available_status_ids = (
        1, # 대여가능
        2, # 대여중
        5, # 세탁
        6, # 수선
        9, # 반납
    );

    my $category = $self->param('category');
    my $gender   = $self->param('gender');
    my $quantity = $DB->resultset('Clothes')->search(
        {
            category  => $category,
            gender    => $gender,
        }
    );
    my $available_quantity = $DB->resultset('Clothes')->search(
        {
            category  => $category,
            gender    => $gender,
            status_id => \@available_status_ids,
        }
    );

    my @items;
    my $criterion = $criterion_of{$category};
    if ($criterion) {
        my $rs = $DB->resultset('Clothes')->search(
            undef,
            {
                columns  => [ $criterion ],
                group_by => $criterion
            },
        );

        while ( my $clothes = $rs->next ) {
            my $size = $clothes->$criterion;

            my $qty           = $DB->resultset('Clothes')->search({ category => $category, gender => $gender, $criterion => $size });
            my $available_qty = $DB->resultset('Clothes')->search({ category => $category, gender => $gender, $criterion => $size, status_id => \@available_status_ids });
            my $rental        = $DB->resultset('Clothes')->search({ category => $category, gender => $gender, $criterion => $size, status_id => 2 });
            my $repair        = $DB->resultset('Clothes')->search({ category => $category, gender => $gender, $criterion => $size, status_id => 6 });
            my $cleaning      = $DB->resultset('Clothes')->search({ category => $category, gender => $gender, $criterion => $size, status_id => 5 });
            my $lost          = $DB->resultset('Clothes')->search({ category => $category, gender => $gender, $criterion => $size, status_id => 7 });
            my $disused       = $DB->resultset('Clothes')->search({ category => $category, gender => $gender, $criterion => $size, status_id => 8 });

            push(
                @items,
                {
                    size          => $size,
                    qty           => $qty,
                    available_qty => $available_qty,
                    rental        => $rental,
                    repair        => $repair,
                    cleaning      => $cleaning,
                    lost          => $lost,
                    disused       => $disused,
                },
            );
        }
    }
    else {
        my $qty           = $DB->resultset('Clothes')->search({ category => $category, gender => $gender });
        my $available_qty = $DB->resultset('Clothes')->search({ category => $category, gender => $gender, status_id => \@available_status_ids });
        my $rental        = $DB->resultset('Clothes')->search({ category => $category, gender => $gender, status_id => 2 });
        my $repair        = $DB->resultset('Clothes')->search({ category => $category, gender => $gender, status_id => 6 });
        my $cleaning      = $DB->resultset('Clothes')->search({ category => $category, gender => $gender, status_id => 5 });
        my $lost          = $DB->resultset('Clothes')->search({ category => $category, gender => $gender, status_id => 7 });
        my $disused       = $DB->resultset('Clothes')->search({ category => $category, gender => $gender, status_id => 8 });

        push(
            @items,
            {
                qty           => $qty,
                available_qty => $available_qty,
                rental        => $rental,
                repair        => $repair,
                cleaning      => $cleaning,
                lost          => $lost,
                disused       => $disused,
            },
        );
    }

    $self->stash(
        items              => \@items,
        quantity           => $quantity,
        available_quantity => $available_quantity,
        criterion          => $criterion,
        gender             => $gender,
    );
} => 'stat-clothes-amount-category-gender';

get '/stat/clothes/hit' => sub {
    my $self = shift;

    my $default_category = 'jacket';
    my $default_gender   = 'male';
    my $default_limit    = 10;

    my $dt_today = DateTime->now( time_zone => app->config->{timezone} );
    my $dt_month_before = $dt_today->clone->subtract( months => 1 );
    unless ($dt_month_before) {
        app->log->warn("cannot create end datetime object");
        $self->redirect_to( $self->url_for('/') );
        return;
    }

    $self->redirect_to(
        $self->url_for( '/stat/clothes/hit/' . $default_category )->query(
            start_date => $dt_month_before->ymd,
            end_date   => $dt_today->ymd,
            gender     => $default_gender,
            limit      => $default_limit,
        )
    );
};

get '/stat/clothes/hit/:category' => sub {
    my $self = shift;

    #
    # fetch params
    #
    my %params = $self->get_params(qw/ start_date end_date category gender limit /);

    #
    # validate params
    #

    my $v = $self->create_validator;
    $v->field('category')->in( keys %{ app->config->{category} } );
    $v->field('gender')->in(qw/ male female /);
    $v->field('limit')->regexp(qr/^\d+$/);

    unless ( $self->validate( $v, \%params ) ) {
        my @error_str;
        while ( my ( $k, $v ) = each %{ $v->errors } ) {
            push @error_str, "$k:$v";
        }
        return $self->error(
            400,
            {
                str  => join( ',', @error_str ),
                data => $v->errors,
            }
        );
    }

    unless ( $params{start_date} ) {
        app->log->warn("start_date is required");
        $self->redirect_to( $self->url_for('/stat/clothes/hit') );
        return;
    }

    unless ( $params{start_date} =~ m/^(\d{4})-(\d{2})-(\d{2})$/ ) {
        app->log->warn("invalid ymd format: $params{start_date}");
        $self->redirect_to( $self->url_for('/start_date') );
        return;
    }

    my $start_date = try {
        DateTime->new(
            time_zone => app->config->{timezone},
            year      => $1,
            month     => $2,
            day       => $3,
        );
    };

    unless ($start_date) {
        app->log->warn("cannot create start datetime object");
        $self->redirect_to( $self->url_for('/stat/clothes/hit') );
        return;
    }

    unless ( $params{end_date} ) {
        app->log->warn("end_date is required");
        $self->redirect_to( $self->url_for('/stat/clothes/hit') );
        return;
    }

    unless ( $params{end_date} =~ m/^(\d{4})-(\d{2})-(\d{2})$/ ) {
        app->log->warn("invalid ymd format: $params{end_date}");
        $self->redirect_to( $self->url_for('/stat/clothes/hit') );
        return;
    }

    my $end_date = try {
        DateTime->new(
            time_zone => app->config->{timezone},
            year      => $1,
            month     => $2,
            day       => $3,
        );
    };
    unless ($end_date) {
        app->log->warn("cannot create end datetime object");
        $self->redirect_to( $self->url_for('/stat/clothes/hit') );
        return;
    }

    #
    # fetch clothes
    #

    my $dtf        = $DB->storage->datetime_parser;
    my $clothes_rs = $DB->resultset('Clothes')->search(
        {
            'category'          => $params{category},
            'gender'            => $params{gender},
            'order.rental_date' => {
                -between => [
                    $dtf->format_datetime($start_date),
                    $dtf->format_datetime($end_date),
                ],
            },
        },
        {
            join       => [
                { order_details => 'order' },
                { donation => 'user' },
            ],
            prefetch   => [ { donation => 'user' } ],
            columns    => [qw/
                arm
                belly
                bust
                category
                code
                color
                hip
                length
                neck
                thigh
                topbelly
                waist
            /],
            '+columns' => [ { count => { count => 'me.id', -as => 'rent_count' } } ],
            group_by   => [qw/ category code /],
            order_by   => { -desc => 'rent_count' },
            rows       => $params{limit},
        }
    );

    $self->render(
        'stat-clothes-hit',
        clothes_rs => $clothes_rs,
        start_date => $start_date,
        end_date   => $end_date,
        category   => $params{category},
        gender     => $params{gender},
        limit      => $params{limit},
    );
};

get '/stat/status' => sub {
    my $self = shift;

    my $dt_today = DateTime->now( time_zone => app->config->{timezone} );
    $self->redirect_to( $self->url_for( '/stat/status/' . $dt_today->ymd ) );
};

get '/stat/status/:ymd' => sub {
    my $self = shift;

    #
    # fetch params
    #
    my %params = $self->get_params(qw/ ymd /);

    unless ( $params{ymd} ) {
        app->log->warn("ymd is required");
        $self->redirect_to( $self->url_for('/stat/visitor') );
        return;
    }

    unless ( $params{ymd} =~ m/^(\d{4})-(\d{2})-(\d{2})$/ ) {
        app->log->warn("invalid ymd format: $params{ymd}");
        $self->redirect_to( $self->url_for('/stat/visitor') );
        return;
    }

    my $dt = try {
        DateTime->new(
            time_zone => app->config->{timezone},
            year      => $1,
            month     => $2,
            day       => $3,
        );
    };
    unless ($dt) {
        app->log->warn("cannot create datetime object");
        $self->redirect_to( $self->url_for('/stat/status') );
        return;
    }

    my $dt_start = try { $dt->clone->truncate( to => 'day' )->add( hours => 24 * 2 * -1 ); };
    unless ($dt_start) {
        app->log->warn("cannot create start datetime object");
        $self->redirect_to( $self->url_for('/stat/status') );
        return;
    }

    my $dt_end = try { $dt->clone->truncate( to => 'day' )->add( hours => 24 * 3, seconds => -1 ); };
    unless ($dt_end) {
        app->log->warn("cannot create end datetime object");
        $self->redirect_to( $self->url_for('/stat/status') );
        return;
    }

    my $basis_dt = try {
        DateTime->new(
            time_zone => app->config->{timezone},
            year      => 2015,
            month     => 5,
            day       => 29
        );
    };
    my $online_order_hour = $dt >= $basis_dt ? 22 : 19;

    my $dtf      = $DB->storage->datetime_parser;
    my $order_rs = $DB->resultset('Order')->search(
        #
        # do not query all data for specific month due to speed
        #
        #\[ 'DATE_FORMAT(`booking`.`date`,"%Y-%m") = ?', $dt->strftime("%Y-%m") ],
        {
            -and => [
                'booking.date' => {
                    -between => [
                        $dtf->format_datetime($dt_start),
                        $dtf->format_datetime($dt_end),
                    ],
                },
                \[ 'HOUR(`booking`.`date`) != ?', $online_order_hour ],
            ]
        },
        {
            join     => [qw/ booking /],
            order_by => { -asc => 'date' },
            prefetch => 'booking',
        },
    );

    $self->render(
        'stat-status',
        order_rs => $order_rs,
        dt       => $dt,
    );
};

get '/shortcut' => 'shortcut';

get '/volunteers' => sub {
    my $self = shift;
    my $status = $self->param('status') || 'reported';
    my $query  = $self->param('q') // '';

    $self->stash(pageset => '');    # prevent undefined error in template

    my ( $works, $standby );
    my $parser = $DB->storage->datetime_parser;
    $works = $DB->resultset('VolunteerWork')
        ->search( { status => $status }, { order_by => 'activity_from_date' } );

    if ( $status eq 'done' ) {
        $works = $works->search(
            {
                activity_from_date =>
                    { '>' => $parser->format_datetime( DateTime->now->subtract( days => 7 ) ) },
                need_1365 => 1,
                done_1365 => { '<>' => 0 },
            },
            {
                order_by => [
                    { -desc => 'need_1365' },
                    { -asc  => 'done_1365' },
                    { -asc  => 'activity_from_date' }
                ]
            }
        );
        $standby = $DB->resultset('VolunteerWork')->search(
            {
                status    => $status,
                need_1365 => 1,
                done_1365 => 0,
            },
            {
                order_by => [
                    { -desc => 'need_1365' },
                    { -asc  => 'done_1365' }
                ]
            }
        );
    }
    elsif ( $status eq 'canceled' ) {
        my $p = $self->param('p') || 1;
        $works = $works->search(
            undef,
            {
                page => $p,
                rows => 10,
                order_by => { -desc => 'id' }
            }
        );

        my $pageset = Data::Pageset->new(
            {
                total_entries    => $works->pager->total_entries,
                entries_per_page => $works->pager->entries_per_page,
                pages_per_set    => 5,
                current_page     => $p,
            }
        );

        $self->stash( pageset => $pageset );
    }

    if ($query) {
        $works = $DB->resultset('VolunteerWork')->search(
            {
                -or => {
                    'volunteer.name'  => $query,
                    'volunteer.phone' => $self->phone_format($query),
                    'volunteer.email' => $query
                }
            },
            { join => 'volunteer' }
        );
    }

    $self->render( works => $works, standby => $standby );
} => 'volunteers-list';

any '/size/guess' => sub {
    my $self   = shift;

    #
    # fetch params
    #
    my %params = $self->get_params(qw/ height weight gender /);

    my $height = $params{height};
    my $weight = $params{weight};
    my $gender = $params{gender};

    my $osg_db = OpenCloset::Size::Guess->new(
        'DB',
        _time_zone => app->config->{timezone},
        _schema    => $DB,
        _range     => 0,
    );

    my $osg_bodykit = OpenCloset::Size::Guess->new(
        'BodyKit',
        _accessKey => app->config->{bodykit}{accessKey},
        _secret    => app->config->{bodykit}{secret},
    );

    my $bestfit_1_order_rs = $DB->resultset('Order')->search(
        {
            bestfit => 1,
            height  => $height,
            weight  => $weight,
        },
        {
            order_by => [
                { -asc => 'me.height' },
                { -asc => 'me.weight' },
            ],
            prefetch => {
                'order_details' => 'clothes',
            },
        },
    );

    my $bestfit_3x3_order_rs = $DB->resultset('Order')->search(
        {
            bestfit => 1,
            height  => {
                -between => [
                    $height - 1,
                    $height + 1,
                ],
            },
            weight  => {
                -between => [
                    $weight - 1,
                    $weight + 1,
                ],
            },
        },
        {
            order_by => [
                { -asc => 'me.height' },
                { -asc => 'me.weight' },
            ],
            prefetch => {
                'order_details' => 'clothes',
            },
        },
    );

    $self->render(
        'size-guess',
        height               => $height,
        weight               => $weight,
        gender               => $gender,
        osg_bodykit          => $osg_bodykit,
        osg_db               => $osg_db,
        bestfit_1_order_rs   => $bestfit_1_order_rs,
        bestfit_3x3_order_rs => $bestfit_3x3_order_rs,
    );
};

get '/stat/visitor' => sub {
    my $self = shift;

    my $dt_today = DateTime->now( time_zone => app->config->{timezone} );
    $self->redirect_to( $self->url_for( '/stat/visitor/' . $dt_today->ymd ) );
};

get '/stat/visitor/:ymd' => sub {
    my $self = shift;

    #
    # fetch params
    #
    my %params = $self->get_params(qw/ ymd /);

    unless ( $params{ymd} ) {
        app->log->warn("ymd is required");
        $self->redirect_to( $self->url_for('/stat/visitor') );
        return;
    }

    unless ( $params{ymd} =~ m/^(\d{4})-(\d{2})-(\d{2})$/ ) {
        app->log->warn("invalid ymd format: $params{ymd}");
        $self->redirect_to( $self->url_for('/stat/visitor') );
        return;
    }

    my $dt = try {
        DateTime->new(
            time_zone => app->config->{timezone},
            year      => $1,
            month     => $2,
            day       => $3,
        );
    };
    unless ($dt) {
        app->log->warn("cannot create datetime object");
        $self->redirect_to( $self->url_for('/stat/visitor') );
        return;
    }

    my $today = try {
        DateTime->now(
            time_zone => app->config->{timezone},
        );
    };
    unless ($today) {
        app->log->warn("cannot create datetime object: today");
        $self->redirect_to( $self->url_for('/stat/visitor') );
        return;
    }
    $today->truncate( to => 'day' );

    # -2 ~ +2 days from now
    my %count;
    my $today_data;
    my $from = $dt->clone->truncate( to => 'day' )->add( days => -2 );
    my $to   = $dt->clone->truncate( to => 'day' )->add( days =>  2 );
    for ( ; $from <= $to; $from->add( days => 1 ) ) {
        my $f = $from->clone->truncate( to => 'day' );
        my $t = $from->clone->truncate( to => 'day' )->add( days => 1, seconds => -1 );

        my $f_str = $f->strftime('%Y%m%d%H%M%S');
        my $t_str = $t->strftime('%Y%m%d%H%M%S');
        my $name  = "day-$f_str-$t_str";

        my $data;
        if ( $f < $today && $t < $today ) {
            $data = $CACHE->get($name);
        }
        elsif ( $f->clone->truncate( to => 'day' ) == $today ) {
            app->log->info( "do not cache and by-pass cache: $name" );
            $data = $self->count_visitor( $f, $t );
            $today_data = $data;
        }

        push @{ $count{day} }, $data;
    }

    # from first to current week of this year
    my $current_week_start_dt;
    my $current_week_end_dt;
    for ( my $i = $today->clone->truncate( to => 'year'); $i <= $today; $i->add( weeks => 1 ) ) {
        my $f = $i->clone->truncate( to => 'week' );
        my $t = $i->clone->truncate( to => 'week' )->add( weeks => 1, seconds => -1 );

        my $f_str = $f->strftime('%Y%m%d%H%M%S');
        my $t_str = $t->strftime('%Y%m%d%H%M%S');
        my $name  = "week-$f_str-$t_str";

        $current_week_start_dt = $f->clone;
        $current_week_end_dt   = $t->clone;

        my $data;
        if ( $f < $today && $t < $today ) {
            $data = $CACHE->get($name);
        }

        push @{ $count{week} }, $data;
    }

    # from january to current months of this year
    my $current_month_start_dt;
    my $current_month_end_dt;
    for ( my $i = $today->clone->truncate( to => 'year'); $i <= $today; $i->add( months => 1 ) ) {
        my $f = $i->clone->truncate( to => 'month' );
        my $t = $i->clone->truncate( to => 'month' )->add( months => 1, seconds => -1 );

        my $f_str = $f->strftime('%Y%m%d%H%M%S');
        my $t_str = $t->strftime('%Y%m%d%H%M%S');
        my $name  = "month-$f_str-$t_str";

        $current_month_start_dt = $f->clone;
        $current_month_end_dt   = $t->clone;

        my $data;
        if ( $f < $today && $t < $today ) {
            $data = $CACHE->get($name);
        }

        push @{ $count{month} }, $data;
    }

    # current data with and without cache
    my %current_week = (
        all        => { total => 0, male => 0, female => 0 },
        visited    => { total => 0, male => 0, female => 0 },
        notvisited => { total => 0, male => 0, female => 0 },
        bestfit    => { total => 0, male => 0, female => 0 },
        loanee     => { total => 0, male => 0, female => 0 },
    );
    my %current_month = (
        all        => { total => 0, male => 0, female => 0 },
        visited    => { total => 0, male => 0, female => 0 },
        notvisited => { total => 0, male => 0, female => 0 },
        bestfit    => { total => 0, male => 0, female => 0 },
        loanee     => { total => 0, male => 0, female => 0 },
    );
    for ( my $i = $today->clone->add( months => -1 )->truncate( to => 'month' ); $i <= $today; $i->add( days => 1 ) ) {
        my $f = $i->clone->truncate( to => 'day' );
        my $t = $i->clone->truncate( to => 'day' )->add( days => 1, seconds => -1 );

        my $f_str = $f->strftime('%Y%m%d%H%M%S');
        my $t_str = $t->strftime('%Y%m%d%H%M%S');
        my $name  = "day-$f_str-$t_str";

        my $data;
        if ( $f < $today && $t < $today ) {
            $data = $CACHE->get($name);
        }
        elsif ( $f->clone->truncate( to => 'day' ) == $today ) {
            app->log->info( "do not cache and by-pass cache: $name" );
            $data = $today_data;
        }

        if ( $current_week_start_dt <= $i && $i <= $current_week_end_dt ) {
            app->log->info( "calculationg for this week: $name" );
            $current_week{all}{total}         += $data->{all}{total};
            $current_week{all}{male}          += $data->{all}{male};
            $current_week{all}{female}        += $data->{all}{female};
            $current_week{visited}{total}     += $data->{visited}{total};
            $current_week{visited}{male}      += $data->{visited}{male};
            $current_week{visited}{female}    += $data->{visited}{female};
            $current_week{notvisited}{total}  += $data->{notvisited}{total};
            $current_week{notvisited}{male}   += $data->{notvisited}{male};
            $current_week{notvisited}{female} += $data->{notvisited}{female};
            $current_week{bestfit}{total}     += $data->{bestfit}{total};
            $current_week{bestfit}{male}      += $data->{bestfit}{male};
            $current_week{bestfit}{female}    += $data->{bestfit}{female};
            $current_week{loanee}{total}      += $data->{loanee}{total};
            $current_week{loanee}{male}       += $data->{loanee}{male};
            $current_week{loanee}{female}     += $data->{loanee}{female};
        }
        if ( $current_month_start_dt <= $i && $i <= $current_month_end_dt ) {
            app->log->info( "calculationg for this month $name" );
            $current_month{all}{total}         += $data->{all}{total};
            $current_month{all}{male}          += $data->{all}{male};
            $current_month{all}{female}        += $data->{all}{female};
            $current_month{visited}{total}     += $data->{visited}{total};
            $current_month{visited}{male}      += $data->{visited}{male};
            $current_month{visited}{female}    += $data->{visited}{female};
            $current_month{notvisited}{total}  += $data->{notvisited}{total};
            $current_month{notvisited}{male}   += $data->{notvisited}{male};
            $current_month{notvisited}{female} += $data->{notvisited}{female};
            $current_month{bestfit}{total}     += $data->{bestfit}{total};
            $current_month{bestfit}{male}      += $data->{bestfit}{male};
            $current_month{bestfit}{female}    += $data->{bestfit}{female};
            $current_month{loanee}{total}      += $data->{loanee}{total};
            $current_month{loanee}{male}       += $data->{loanee}{male};
            $current_month{loanee}{female}     += $data->{loanee}{female};
        }
    }
    $count{week}[-1]  = \%current_week;
    $count{month}[-1] = \%current_month;

    $self->render(
        'stat-visitor',
        count => \%count,
        dt    => $dt,
    );
};

get '/order/:order_id/return' => sub {
    my $self = shift;

    my $order_id = $self->param('order_id');
    my $order    = $self->get_order( { id => $order_id } );
    return unless $order;

    my $error = $self->flash('error');
    $self->render('order-return', order => $order, error => $error);
};

post '/order/:order_id/return' => sub {
    my $self     = shift;
    my $order_id = $self->param('order_id');
    my $order    = $self->get_order( { id => $order_id } );
    return unless $order;

    ## parameters validation
    my $v = $self->validation;
    $v->required('parcel');
    $v->required('phone');
    $v->required('waybill');

    if ( $v->has_error ) {
        my $errors = {};
        my $failed = $v->failed;
        map { $errors->{$_} = $v->error($_) } @$failed;
        $self->flash(error => $errors);
        return $self->redirect_to($self->url_for);
    }

    my $parcel  = $v->param('parcel');
    my $phone   = $v->param('phone');
    my $waybill = $v->param('waybill');

    ## phone number validation
    my $user_phone = $order->user->user_info->phone;
    if ( $phone ne $user_phone ) {
        $self->flash(error => { phone => ['대여예약시에 사용했던 동일한 핸드폰 번호를 입력해주세요'] });
        return $self->redirect_to($self->url_for);
    }

    $self->update_order({ id => $order_id, return_method => join( ',', $parcel, $waybill ) });
    $self->redirect_to( $self->url_for("/order/$order_id/return/success") );
};

get '/order/:order_id/return/success' => sub {
    my $self = shift;

    my $order_id = $self->param('order_id');
    my $order    = $self->get_order( { id => $order_id } );
    return unless $order;

    $self->render('order-return-success', order => $order);
};

get '/order/:order_id/extension' => sub {
    my $self = shift;

    my $order_id = $self->param('order_id');
    my $order    = $self->get_order( { id => $order_id } );
    return unless $order;

    my $error = $self->flash('error');
    $self->render('order-extension', order => $order, error => $error);
};

post '/order/:order_id/extension' => sub {
    my $self     = shift;
    my $order_id = $self->param('order_id');
    my $order    = $self->get_order({ id => $order_id });
    return unless $order;

    ## parameters validation
    my $v = $self->validation;
    $v->required('phone');
    $v->required('user-target-date');

    if ( $v->has_error ) {
        my $errors = {};
        my $failed = $v->failed;
        map { $errors->{$_} = $v->error($_) } @$failed;
        $self->flash(error => $errors);
        return $self->redirect_to($self->url_for);
    }

    my $phone       = $v->param('phone');
    my $target_date = $v->param('user-target-date');

    ## phone number validation
    my $user_phone = $order->user->user_info->phone;
    if ( $phone ne $user_phone ) {
        $self->flash(error => { phone => ['대여예약시에 사용했던 동일한 핸드폰 번호를 입력해주세요'] });
        return $self->redirect_to($self->url_for);
    }

    $self->update_order({ id => $order_id, user_target_date => $target_date });
    $self->redirect_to( $self->url_for("/order/$order_id/extension/success") );
};

get '/order/:order_id/extension/success' => sub {
    my $self = shift;

    my $order_id = $self->param('order_id');
    my $order    = $self->get_order( { id => $order_id } );
    return unless $order;

    $self->render('order-extension-success', order => $order);
};

app->secrets( app->defaults->{secrets} );
app->start;
