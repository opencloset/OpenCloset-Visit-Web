package OpenCloset::Web::Controller::API;
use Mojo::Base 'Mojolicious::Controller';

use DateTime  ();
use Encode    ();
use Try::Tiny ();

use Postcodify ();

=head1 METHODS

=head2 create_sms_validation

    POST /api/sms/validation

=cut

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
    $v->field('name')->required(1)->trim(0)->callback(
        sub {
            my $value = shift;

            return 1 unless $value =~ m/(^\s+|\s+$)/;
            return ( 0, "name has trailing space" );
        }
    );
    $v->field('to')->required(1)->regexp(qr/^\d+$/);

    unless ( $self->validate( $v, \%params ) ) {
        my @error_str;
        while ( my ( $k, $v ) = each %{ $v->errors } ) {
            push @error_str, "$k:$v";
        }
        $self->error( 400, { str => join( ',', @error_str ), data => $v->errors, } ), return;
    }

    #
    # find user
    #
    my @users = $self->app->DB->resultset('User')
        ->search( { 'user_info.phone' => $params{to} }, { join => 'user_info' }, );
    my $user = shift @users;

    if ($user) {
        #
        # fail if name and phone does not match
        #
        unless ( $user->name eq $params{name} ) {
            my $msg = sprintf(
                'name and phone does not match: input(%s,%s), db(%s,%s)',
                $params{name}, $params{to}, $user->name, $user->user_info->phone,
            );
            $self->app->log->warn($msg);

            $self->error( 400, { str => 'name and phone does not match', } ), return;
        }
    }
    else {
        #
        # add user using one's name and phone if who does not exist
        #
        {
            my $guard = $self->app->DB->txn_scope_guard;

            my $_user = $self->app->DB->resultset('User')->create( { name => $params{name} } );
            unless ($_user) {
                $self->app->log->warn('failed to create a user');
                last;
            }

            my $_user_info = $self->app->DB->resultset('UserInfo')
                ->create( { user_id => $_user->id, phone => $params{to}, } );
            unless ($_user_info) {
                $self->app->log->warn('failed to create a user_info');
                last;
            }

            $guard->commit;

            $user = $_user;
        }

        $self->app->log->info("create a user: name($params{name}), phone($params{to})");
    }

    #
    # fail if creating user is failed
    #
    unless ($user) {
        $self->error( 400, { str => 'failed to create a user', } ), return;
    }

    my $authcode = String::Random->new->randregex('\d\d\d\d\d\d');
    my $expires =
        DateTime->now( time_zone => $self->config->{timezone} )->add( minutes => 20 );
    $user->update( { authcode => $authcode, expires => $expires->epoch, } )
        or return $self->error( 500, { str => 'failed to update a user', data => {}, } );
    $self->app->log->debug(
        "sent temporary authcode: to($params{to}) authcode($authcode)");

    my $sms = $self->app->DB->resultset('SMS')->create(
        {
            to   => $params{to},
            from => $self->config->{sms}{ $self->config->{sms}{driver} }{_from},
            text => "열린옷장 인증번호: $authcode",
        }
    );
    return $self->error( 404, { str => 'failed to create a new sms', data => {}, } )
        unless $sms;

    #
    # response
    #
    my %data = ( $sms->get_columns );

    $self->res->headers->header(
        'Location' => $self->url_for( '/api/sms/' . $sms->id ),
    );
    $self->respond_to( json => { status => 201, json => \%data } );
}

=head2 postcode_preflight_cors

    OPTIONS /api/postcode/search

=cut

sub api_postcode_preflight_cors {
    my $self = shift;

    my $origin = $self->req->headers->header('origin');
    my $method = $self->req->headers->header('access-control-request-method');

    $self->res->headers->header( 'Access-Control-Allow-Origin'  => $origin );
    $self->res->headers->header( 'Access-Control-Allow-Methods' => $method );
    $self->respond_to( any => { data => '', status => 200 } );
}

=head2 postcode_search

    GET /api/postcode/search

=cut

sub api_postcode_search {
    my $self = shift;
    my $q    = $self->param('q');

    my $origin = $self->req->headers->header('origin');
    $self->res->headers->header( 'Access-Control-Allow-Origin' => $origin );

    if ( length $q < 3 || length $q > 80 ) {
        return $self->error( 400, { str => 'Query is too long or too short : ' . $q } );
    }

    my $p = Postcodify->new( config => $ENV{MOJO_CONFIG} || './app.psgi.conf' );
    my $result = $p->search($q);
    $self->app->log->info("postcode search query: $q");
    $self->render( text => Encode::decode_utf8( $result->json ), format => 'json' );
}

=head2 gui_booking_list

    GET /api/gui/booking-list

=cut

sub api_gui_booking_list {
    my $self = shift;

    #
    # fetch params
    #
    my %params = $self->get_params(qw/ gender ymd include_empty /);

    #
    # validate params
    #
    my $v = $self->create_validator;
    $v->field('gender')->in(qw/ male female /);
    $v->field('ymd')->callback(
        sub {
            my $val = shift;

            unless ( $val =~ m/^(\d{4})-(\d{2})-(\d{2})$/ ) {
                my $msg = "invalid ymd format: $params{ymd}";
                $self->app->log->warn($msg);
                return ( 0, $msg );
            }

            my $dt = Try::Tiny::try {
                DateTime->new(
                    time_zone => $self->config->{timezone},
                    year      => $1,
                    month     => $2,
                    day       => $3,
                );
            };
            unless ($dt) {
                my $msg = "cannot create start datetime object: $params{ymd}";
                $self->app->log->warn($msg);
                return ( 0, $msg );
            }

            return 1;
        }
    );
    unless ( $self->validate( $v, \%params ) ) {
        my @error_str;
        while ( my ( $k, $v ) = each %{ $v->errors } ) {
            push @error_str, "$k:$v";
        }
        return $self->error( 400, { str => join( ',', @error_str ), data => $v->errors, } );
    }

    #
    # [GH 996] 예약 화면에서 주문서의 예약시간을 변경
    #
    my ( $from, $to );
    if ( $params{ymd} ) {
        $params{ymd} =~ m/^(\d{4})-(\d{2})-(\d{2})$/;
        $from = DateTime->new(
            time_zone => $self->config->{timezone},
            year      => $1,
            month     => $2,
            day       => $3,
        );
        unless ($from) {
            my $msg = "cannot create start datetime object";
            $self->log->warn($msg);
            $self->error( 500, { str => $msg, data => {}, } );
            return;
        }

        $to = $from->clone->truncate( to => 'day' )->add( hours => 24 * 1, seconds => -1 );
        unless ($to) {
            my $msg = "cannot create end datetime object";
            $self->app->log->warn($msg);
            $self->error( 500, { str => $msg, data => {}, } );
            return;
        }
    }

    my $include_empty = $params{include_empty};

    #
    # [GH 1366] 서울시 쿠폰 유효기간의 수정
    #
    if ( $self->session->{coupon_code} ) {
        my $coupon = $self->app->DB->resultset("Coupon")
            ->find( { code => $self->session->{coupon_code} } );
        if ($coupon) {
            my ( $event_name ) = split /\|/, $coupon->desc;

            #
            # [GH 1517] 쿠폰 시스템의 개선
            #
            my $event = $coupon->event;
            unless ($event) {
                $event = $self->app->DB->resultset('Event')->search({ name => $event_name })->next;
            }

            if ($event && $event->event_type) {
                my $event_type = $event->event_type;
                my $type = $event_type->type;
                my ($start_type, $end_type) = split /\|/, $type;
                if ($end_type eq 'rental') {
                    ## 쿠폰의 expires_date 는 보통 null 일 테지만, 설정을 했다면 이유가 있으므로
                    ## 이벤트 종료일보다 높은 우선순위를 둔다.
                    $to = $coupon->expires_date || $event->end_date;
                } elsif($end_type eq 'reserve') {
                    ## reserve 타입은 쿠폰코드를 입력하는 시점에 유효성 검사를 함
                    ## 쿠폰 유효성 체크를 통과했다면 이후에는 일반 대여와 같다.
                } else {
                    $self->log->error("Unknown event_type.type: $type");
                }
            } elsif (  $self->config->{events}{$event_name}
                    && $self->config->{events}{$event_name}{booking_expires} ) {
                $self->config->{events}{$event_name}{booking_expires}
                    =~ m/^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})$/;
                $to = DateTime->new(
                    time_zone => $self->config->{timezone},
                    year      => $1,
                    month     => $2,
                    day       => $3,
                    hour      => $4,
                    minute    => $5,
                    second    => $6,
                );
                unless ($to) {
                    my $msg = "cannot create end datetime object";
                    $self->app->log->warn($msg);
                    $self->error( 500, { str => $msg, data => {}, } );
                    return;
                }
            }
        }
    }

    my @booking_list = $self->booking_list( $params{gender}, $from, $to, $include_empty );
    return unless @booking_list;

    #
    # response
    #
    $self->respond_to( json => { status => 200, json => \@booking_list } );
}

1;
