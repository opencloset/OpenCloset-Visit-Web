#!/usr/bin/env perl

use v5.18;
use Mojolicious::Lite;

use DateTime;
use Encode 'decode_utf8';
use File::ShareDir "dist_dir";
use HTTP::Tiny;
use List::MoreUtils qw( zip );
use Path::Tiny;
use String::Random;
use Try::Tiny;

use Postcodify;

use OpenCloset::Schema;

app->defaults( %{ plugin 'Config' => { default => {
    jses        => [],
    csses       => [],
    breadcrumbs => [],
    active_id   => q{},
    page_id     => q{},
    alert       => q{},
    type        => q{},
}}});

my $DB = OpenCloset::Schema->connect({
    dsn      => app->config->{database}{dsn},
    user     => app->config->{database}{user},
    password => app->config->{database}{pass},
    %{ app->config->{database}{opts} },
});

plugin 'AssetPack' => {
    pipes => [
        qw/
            Sass
            Css
            CoffeeScript
            JavaScript
            Fetch
            Combine
            /
    ],
};

{
    # use content from directories under lib/OpenCloset/Visit/Web/files or using File::ShareDir
    my $lib_base = path( path(__FILE__)->absolute->dirname . "/Web/files" )->child("/public");
    my $dist_dir = try { path( dist_dir("OpenCloset-Visit-Web") )->child("/public") };
    my $cur_dir  = path("./public");

    my $final =
          $lib_base && $lib_base->is_dir ? $lib_base->stringify
        : $dist_dir && $dist_dir->is_dir ? $dist_dir->stringify
        : $cur_dir  && $cur_dir->is_dir  ? $cur_dir->stringify
        :                                  undef;
    push @{ app->asset->store->paths }, $final if $final;

    # FIXME
    push @{ app->static->paths }, "./assets";

    app->asset->process;
}

plugin 'FillInFormLite';
plugin 'haml_renderer';
plugin 'validator';

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

helper meta_text => sub {
    my ( $self, $id ) = @_;

    my $meta = app->config->{sidebar}{meta};

    return $meta->{$id}{text};
};

helper commify => sub {
    my $self = shift;
    local $_ = shift;
    1 while s/((?:\A|[^.0-9])[-+]?\d+)(\d{3})/$1,$2/s;
    return $_;
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

        my $req_path = $self->req->url->path;
        given ($req_path) {
            when ('/visit') {
                return 1;
            }
            default {
                app->log->warn( "$req_path is not allowed" );
                $self->redirect_to( $self->url_for('/visit') );
                return;
            }
        }
    }

    return;
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

    app->log->debug( "type: " .          ( $type          || q{} ) );
    app->log->debug( "name: " .          ( $name          || q{} ) );
    app->log->debug( "phone: " .         ( $phone         || q{} ) );
    app->log->debug( "service: " .       ( $service       || q{} ) );
    app->log->debug( "privacy: " .       ( $privacy       || q{} ) );
    app->log->debug( "sms: " .           ( $password      || q{} ) );
    app->log->debug( "email: " .         ( $email         || q{} ) );
    app->log->debug( "gender: " .        ( $gender        || q{} ) );
    app->log->debug( "address1: " .      ( $address1      || q{} ) );
    app->log->debug( "address2: " .      ( $address2      || q{} ) );
    app->log->debug( "address3: " .      ( $address3      || q{} ) );
    app->log->debug( "address4: " .      ( $address4      || q{} ) );
    app->log->debug( "birth: " .         ( $birth         || q{} ) );
    app->log->debug( "order: " .         ( $order         || q{} ) );
    app->log->debug( "booking: " .       ( $booking       || q{} ) );
    app->log->debug( "booking-saved: " . ( $booking_saved || q{} ) );
    app->log->debug( "wearon_date: " .   ( $wearon_date   || q{} ) );
    app->log->debug( "purpose: " .       ( $purpose       || q{} ) );
    app->log->debug( "purpose2: " .      ( $purpose2      || q{} ) );
    app->log->debug( "pre_category: " .  ( $pre_category  || q{} ) );
    app->log->debug( "pre_color: " .     ( $pre_color     || q{} ) );

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

app->secrets( app->defaults->{secrets} );
app->start;
