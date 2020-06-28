package OpenCloset::Web::Plugin::Helpers;

use Mojo::Base 'Mojolicious::Plugin';

use experimental qw( signatures );

use DateTime        ();
use HTTP::Tiny      ();
use List::MoreUtils ();
use Mojo::Util      ();
use Mojo::JSON      ();

use OpenCloset::Constants::Status ();

=encoding utf8

=head1 NAME

OpenCloset::Web::Plugin::Helpers - opencloset web mojo helper

=head1 SYNOPSIS

    # Mojolicious::Lite
    plugin 'OpenCloset::Web::Plugin::Helpers';

    # Mojolicious
    $self->plugin('OpenCloset::Web::Plugin::Helpers');

=cut

sub register ( $self, $app, $conf ) {
    $app->helper( error                     => \&error );
    $app->helper( flatten_booking           => \&flatten_booking );
    $app->helper( flatten_user              => \&flatten_user );
    $app->helper( get_params                => \&get_params );
    $app->helper( update_user               => \&update_user );
    $app->helper( get_nearest_booked_order  => \&get_nearest_booked_order );
    $app->helper( booking_list              => \&booking_list );
    $app->helper( prefer_category_to_string => \&prefer_category_to_string );
}

=head1 HELPERS

=head2 error( $status, $error )

=cut

sub error ( $self, $status, $error, $template = q{} ) {
    if ( defined $error->{str} ) {
        $self->app->log->error( $error->{str} );
    }
    elsif ( $error->{data} && $error->{data}{error} ) {
        $self->app->log->error( $error->{data}{error} );
    }
    $self->app->log->debug("template: $template") if $template;

    unless ($template) {
        no warnings 'experimental';
        given ($status) {
            $template = 'bad_request' when 400;
            $template = 'unauthorized' when 401;
            $template = 'not_found' when 404;
            $template = 'exception' when 500;
            default { $template = 'unknown' }
        }
    }

    $self->respond_to(
        json => { status => $status, json => { error => $error || q{} } },
        html => { status => $status, error => $error->{str} || q{}, template => $template },
    );

    return;
}

=head2 flatten_booking( $booking )

=cut

sub flatten_booking {
    my ( $self, $booking ) = @_;

    return unless $booking;

    my %data = $booking->get_columns;

    return \%data;
}

=head2 flatten_user( $user )

=cut

sub flatten_user {
    my ( $self, $user ) = @_;

    return unless $user;

    my %data = ( $user->user_info->get_columns, $user->get_columns, );
    delete @data{qw/ user_id password /};

    return \%data;
}

=head2 get_params( @keys )

=cut

sub get_params ( $self, @keys ) {
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
    my %params = List::MoreUtils::zip @dest_keys, @values;

    #
    # remove not defined parameter key and values
    #
    defined $params{$_} ? 1 : delete $params{$_} for keys %params;

    return %params;
}

=head2 update_user( $user_params, $user_info_params )

=cut

sub update_user ( $self, $user_params, $user_info_params ) {
    #
    # validate params
    #
    my $v = $self->app->validator->validation->input( { %$user_params, %$user_info_params } );
    $v->required("id")->like(qr/^\d+$/);
    $v->optional( "name", "trim" )->size( 2, undef );
    $v->optional("email")->email();
    $v->optional("expires")->like(qr/^\d+$/);
    $v->optional("phone", "trim")->phone();
    $v->optional("gender")->in( "male", "female" );
    $v->optional("birth")->num( 1900, 2099 );
    $v->optional($_)->num( 0, 999 )
        for
        qw( height weight neck bust waist hip topbelly belly thigh arm leg knee foot pants );
    $v->optional("staff")->num( 0, 1 );
    my @invalid_fields;
    my @fields = qw(
        id
        name
        email
        expires
        phone
        gender
        birth
        height
        weight
        neck
        bust
        waist
        hip
        topbelly
        belly
        thigh
        arm
        leg
        knee
        foot
        pants
        staff
    );
    for my $field (@fields) {
        push @invalid_fields, $field if $v->has_error($field);
    }
    if ( $v->has_error ) {
        my $msg = "invalid params: " . join(", ", @invalid_fields);
        $self->error( 400, { str => $msg, data => {}, } );
        return;
    }

    if ( $v->param("name") ) {
        $user_params->{name} = $v->param("name");
    }
    if ( $v->param("phone") ) {
        $user_info_params->{phone} = $v->param("phone");
        $user_info_params->{phone} =~ s/\D//gms;
    }

    #
    # find user
    #
    my $user = $self->app->DB->resultset('User')->find( { id => $user_params->{id} } );
    return $self->error( 404, { str => 'user not found', data => {}, } ) unless $user;
    return $self->error( 404, { str => 'user info not found', data => {}, } )
        unless $user->user_info;

    #
    # update user
    #
    {
        my $guard = $self->app->DB->txn_scope_guard;

        my %_user_params = %$user_params;
        delete $_user_params{id};

        if ( $_user_params{create_date} ) {
            $_user_params{create_date} = DateTime->from_epoch(
                epoch     => $_user_params{create_date},
                time_zone => $self->config->{timezone},
            );
        }
        if ( $_user_params{update_date} ) {
            $_user_params{update_date} = DateTime->from_epoch(
                epoch     => $_user_params{update_date},
                time_zone => $self->config->{timezone},
            );
        }

        #
        # [GH #1371] 신체 사이즈 수치를 지워도 NULL이 아닌 0이 저장됨
        #
        my %_user_info_params = %$user_info_params;
        my %_old_user_info;
        for my $k ( keys %_user_info_params ) {
            $_user_info_params{$k} = undef if $_user_info_params{$k} eq q{};
            $_old_user_info{$k} = $user->user_info->get_column($k);
        }

        $user->update( \%_user_params )
            or return $self->error( 500, { str => 'failed to update a user', data => {}, } );

        $user->user_info->update( { %_user_info_params, user_id => $user->id, } )
            or return $self->error(
            500,
            { str => 'failed to update a user info', data => {}, }
            );

        $guard->commit;

        #
        # [GH #1390] 신체 치수 변경 시 디버그를 위한 로그를 표시
        #
        $self->app->log->debug(
            sprintf(
                "update user_info: user.id(%d), user_info.id(%d), %s -> %s",
                $user->id,
                $user->user_info->id,
                Mojo::Util::decode( "UTF-8", Mojo::JSON::encode_json( \%_old_user_info ) ),
                Mojo::Util::decode( "UTF-8", Mojo::JSON::encode_json( \%_user_info_params ) ),
            )
        );

        #
        # event posting to opencloset/monitor
        #
        my $monitor_uri_full = $self->config->{monitor_uri} . "/events";
        my $res = HTTP::Tiny->new( timeout => 1 )->post_form(
            $monitor_uri_full,
            { sender => 'user', user_id => $user->id },
        );
        $self->app->log->warn(
            "Failed to post event to monitor: $monitor_uri_full: $res->{reason}")
            unless $res->{success};
    }

    return $user;
}

=head2 get_nearest_booked_order( $user )

=cut

sub get_nearest_booked_order ( $self, $user ) {
    my $dt_now = DateTime->now( time_zone => $self->config->{timezone} );
    my $dtf = $self->app->DB->storage->datetime_parser;

    my $rs = $user->search_related(
        'orders',
        {
            'me.status_id' => {
                -in => [
                    $OpenCloset::Constants::Status::RESERVATED, # 방문예약
                    $OpenCloset::Constants::Status::PAYMENT,    # 결제대기
                ],
            },
        },
        {
            join => 'booking', order_by => [ { -asc => 'booking.date' }, { -asc => 'me.id' }, ],
        },
        )->search_literal(
        'DATE_FORMAT(`booking`.`date`, "%Y-%m-%d") >= ?',
        $dt_now->ymd
        );

    my $order = $rs->next;

    return $order;
}

=head2 booking_list( $gender [, $from, $to, $include_empty ] )

    my @list = $self->booking_list('male');

=cut

sub booking_list ( $self, $gender, $from = undef, $to = undef, $include_empty = undef ) {
    #
    # find booking
    #
    my $dt_start = $from;
    unless ($dt_start) {
        $dt_start = DateTime->now( time_zone => $self->config->{timezone} );
        unless ($dt_start) {
            my $msg = "cannot create start datetime object";
            $self->app->log->warn($msg);
            $self->error( 500, { str => $msg, data => {}, } );
            return;
        }
    }

    my $dt_end = $to;
    unless ($dt_end) {
        $dt_end = $dt_start->clone->truncate( to => 'day' )
            ->add( hours => 24 * 15, seconds => -1 );
        unless ($dt_end) {
            my $msg = "cannot create end datetime object";
            $self->app->log->warn($msg);
            $self->error( 500, { str => $msg, data => {}, } );
            return;
        }
    }

    my %search_attrs = (
        '+columns' => [ { user_count => { count => 'user.id', -as => 'user_count' } }, ],
        join     => { 'orders' => 'user' },
        group_by => [qw/ me.id /],
        order_by => { -asc     => 'me.date' },
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
    my $dtf        = $self->app->DB->storage->datetime_parser;
    my $booking_rs = $self->app->DB->resultset('Booking')->search(
        {
            'me.id'     => { '!=' => undef },
            'me.gender' => $gender,
            'me.date'   => {
                -between => [ $dtf->format_datetime($dt_start), $dtf->format_datetime($dt_end), ],
            },
        },
        \%search_attrs,
    );

    my @booking_list = $booking_rs->all;
    unless (@booking_list) {
        $self->error( 404, { str => 'booking list not found', data => {}, } );
        return;
    }

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

        unless ( $self->is_user_authenticated
            && $self->current_user
            && $self->current_user->user_info
            && $self->current_user->user_info->staff )
        {
            unless ( $include_empty ) {
                next unless $flat->{slot} > 0;
            }

            $flat->{id} = 0 unless $flat->{slot} > $flat->{user_count};
        }

        push @data, $flat;
    }

    return @data;
}

=head2 prefer_category_to_string($prefer_category)

    my $str = $self->prefer_category_to_string($prefer_category);

=cut

sub prefer_category_to_string ( $self, $items ) {
    use experimental qw( smartmatch );

    return unless $items;
    return unless ref($items) ~~ [ "ARRAY", "HASH" ];

    $items = [ $items ] if ref $items eq "HASH";

    my @result;
    for my $item (@$items) {
        next unless exists $item->{id};
        next unless exists $item->{count};
        next unless exists $item->{state};

        next unless $item->{state};
        next unless $item->{count} > 0;
        push @result, "$item->{id}:$item->{count}";
    }

    return join( q{,}, @result );
}

1;
