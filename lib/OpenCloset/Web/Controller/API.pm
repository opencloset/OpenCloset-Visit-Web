package OpenCloset::Web::Controller::API;
use Mojo::Base 'Mojolicious::Controller';

use experimental qw( signatures );

use Capture::Tiny              ();
use DateTime                   ();
use DateTime::Format::Strptime ();
use Encode                     ();
use Try::Tiny                  ();

use Postcodify ();

use OpenCloset::Constants::Status ();

use OpenCloset::API::Order ();

=head1 METHODS

=head2 create_sms_validation

    POST /api/sms/validation

=cut

sub api_create_sms_validation {
    my $self = shift;

    #
    # fetch params
    #
    my %params = $self->get_params(qw/ name to gender /);

    #
    # validate params
    #
    my $v = $self->app->validator->validation->input(\%params);
    $v->required( "name", "trim" )->size( 2, undef );
    $v->required( "to", "trim" )->phone();
    $v->required("gender")->in( "male", "female" );
    my @invalid_fields;
    my @fields = qw(
        name
        to
        gender
    );
    for my $field (@fields) {
        push @invalid_fields, $field if $v->has_error($field);
    }
    if ( $v->has_error ) {
        my $msg = "invalid params: " . join(", ", @invalid_fields);
        $self->error( 400, { str => $msg, data => {}, } );
        return;
    }

    $params{name} = $v->param("name");
    $params{to}   = $v->param("to");
    $params{to} =~ s/\D//gms;

    #
    # find user
    #
    my $user = $self->app->DB->resultset("User")->search(
        {
            "user_info.phone"  => $params{to},
        },
        {
            join     => "user_info",
            prefetch => "user_info",
        },
    )->first;
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

            $self->error( 400, { str => "name and phone does not match", } ), return;
        }
        #
        # fail if gender and phone does not match
        #
        unless ( $user->user_info->gender eq $params{gender} ) {
            my $msg = sprintf(
                'gender and phone does not match: input(%s,%s), db(%s,%s)',
                $params{gender}, $params{to}, $user->user_info->gender, $user->user_info->phone,
            );
            $self->app->log->warn($msg);

            $self->error( 400, { str => "gender and phone does not match", } ), return;
        }
    }
    else {
        #
        # add user using one's name and phone if who does not exist
        #
        {
            my $guard = $self->app->DB->txn_scope_guard;

            my $_user = $self->app->DB->resultset("User")->create( { name => $params{name} } );
            unless ($_user) {
                $self->app->log->warn("failed to create a user");
                last;
            }

            my $_user_info = $self->app->DB->resultset("UserInfo")->create(
                {
                    user_id => $_user->id,
                    phone   => $params{to},
                    gender  => $params{gender},
                }
            );
            unless ($_user_info) {
                $self->app->log->warn("failed to create a user_info");
                last;
            }

            $guard->commit;

            $user = $_user;
        }

        $self->app->log->info("create a user: name($params{name}), phone($params{to}), gender($params{gender})");
    }

    #
    # fail if creating user is failed
    #
    unless ($user) {
        $self->error( 400, { str => "failed to create a user", } ), return;
    }

    my $authcode = String::Random->new->randregex('\d\d\d\d\d\d');
    my $expires =
        DateTime->now( time_zone => $self->config->{timezone} )->add( minutes => 20 );
    $user->update( { authcode => $authcode, expires => $expires->epoch, } )
        or return $self->error( 500, { str => "failed to update a user", data => {}, } );
    $self->app->log->debug(
        "sent temporary authcode: to($params{to}) authcode($authcode)");

    my $sms = $self->app->DB->resultset("SMS")->create(
        {
            to   => $params{to},
            from => $self->config->{sms}{ $self->config->{sms}{driver} }{_from},
            text => "열린옷장 인증번호: $authcode",
        }
    );
    return $self->error( 404, { str => "failed to create a new sms", data => {}, } )
        unless $sms;

    #
    # response
    #
    my %data = ( $sms->get_columns );
    delete $data{text};
    use DDP; $self->log->info( np(%data) );

    $self->res->headers->header(
        "Location" => $self->url_for( "/api/sms/" . $sms->id ),
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
    my $v = $self->app->validator->validation->input(\%params);
    $v->required("gender")->in( "male", "female" );
    $v->required("ymd")->booking_ymd();
    $v->optional("include_empty");
    my @invalid_fields;
    my @fields = qw(
        gender
        ymd
    );
    for my $field (@fields) {
        push @invalid_fields, $field if $v->has_error($field);
    }
    if ( $v->has_error ) {
        my $msg = "invalid params: " . join(", ", @invalid_fields);
        $self->error( 400, { str => $msg, data => {}, } );
        return;
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

=head2 api_create_order

    POST /api/order

=cut

sub api_create_order {
    my $self = shift;

    my $data = $self->req->json;
    use DDP; $self->app->log->info("api_create_order: " . np($data));
    my $v = $self->app->validator->validation->input($data);

    # 개인 기본 정보: sms, gender, name 은 인증번호 확인 시점에 확인이 끝났음
    $v->required("phone")->phone;

    # 개인 추가 정보
    $v->required("birth")->num(1950, 2010);
    $v->required("email")->email;
    $v->required("address1")->length(1);
    $v->required("address2")->length(1);
    $v->required("address3")->length(1);
    $v->required("address4")->length(1);

    # 주문 정보
    $v->required("booking_id")->num( 1, undef );
    $v->required("wear_self")->in( "self", "other" );
    $v->optional("wear_gender")->in( "male", "female" );
    $v->required("purpose")->length(1);
    $v->required("purpose2")->length(1);
    $v->required("prefer_style")->in( "basic", "casual" );
    $v->required("prefer_color")->in( "staff", "dark", "black", "navy", "charcoalgray", "gray", "brown", "etc" );
    $v->required("prefer_category")->prefer_category();
    $v->required("wear_ymd")->like(qr/^\d{4}-\d{2}-\d{2}$/);

    my @invalid_fields;
    my @fields = qw(
        phone
        birth
        email
        address1
        address2
        address3
        address4
        booking_id
        wear_self
        wear_gender
        purpose
        purpose2
        prefer_style
        prefer_color
        prefer_category
        wear_ymd
    );
    for my $field (@fields) {
        push @invalid_fields, $field if $v->has_error($field);
    }

    # Check if validation is failed
    if ( $v->has_error ) {
        my $msg = "invalid params: " . join(", ", @invalid_fields);
        $self->error( 400, { str => $msg, data => {}, } );
        return;
    }

    # Check relation between wear_self & wear_gender
    my $wear_self = $v->param("wear_self");
    my $wear_gender = $v->param("wear_gender");
    if ( $wear_self eq "self" ) {
        if ($wear_gender) {
            my $msg = "wear_gender must be empty if wear_self is self";
            $self->error( 400, { str => $msg, data => {}, } );
            return;
        }
    }
    else {
        unless ($wear_gender) {
            my $msg = "wear_gender must exist unless wear_self is self";
            $self->error( 400, { str => $msg, data => {}, } );
            return;
        }
    }

    #
    # find user
    #
    my $user;
    my $user_info;
    my $phone = $v->param("phone");
    {
        my @users = $self->app->DB->resultset("User")->search(
            { "user_info.phone" => $phone },
            { join              => "user_info" },
        );
        $user = shift @users;
        unless ($user) {
            my $msg = "cannot find user using phone: [$phone]";
            $self->error( 400, { str => $msg, data => {}, } );
            return;
        }
        $user_info = $user->user_info;
        unless ($user_info) {
            my $msg = "cannot find user_info using phone: [$phone]";
            $self->error( 400, { str => $msg, data => {}, } );
            return;
        }
    }
    $self->log->debug("u.name: " . $user->name);
    $self->log->debug("ui.gender: " . $user_info->gender);

    # check email & birth
    my $email = $v->param("email");
    my $birth = $v->param("birth");
    {
        if ( $user->email && !( $email eq $user->email ) ) {
            my $msg = "unmatched email: $email";
            $self->error( 400, { str => $msg, data => {}, } );
            return;
        }
        if ( $user_info->birth && !( $birth eq $user_info->birth ) ) {
            my $msg = "unmatched birth: $birth";
            $self->error( 400, { str => $msg, data => {}, } );
            return;
        }
    }
    $self->log->debug("email: " . $email);
    $self->log->debug("birth: " . $birth);

    # 신규 예약 신청
    my %data;
    my ( $success, $error ) = Try::Tiny::try {
        my $schema = $self->app->DB;
        my $guard  = $schema->txn_scope_guard;

        # $booking_obj 이 없다면 오류
        my $booking_obj;
        do {
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
            # WHERE `me`.`id` = ?
            # GROUP BY `me`.`id` HAVING COUNT(user.id) < me.slot
            #
            # http://stackoverflow.com/questions/5285448/mysql-select-only-not-null-values
            # https://metacpan.org/pod/DBIx::Class::Manual::Joining#Across-multiple-relations
            #
            my $booking_rs = $self->app->DB->resultset("Booking")->search(
                { "me.id" => $v->param("booking_id") },
                {
                    "+columns" => [ { user_count => { count => "user.id", -as => "user_count" } }, ],
                    join       => { "orders" => "user" },
                    group_by   => [qw/ me.id /],
                },
            );
            $booking_obj = $booking_rs->first;
            unless ($booking_obj) {
                my $msg = "booking item not found";
                $self->error( 500, { str => $msg, data => {}, } );
                return;
            }
        };
        $data{booking} = $self->app->flatten_booking($booking_obj);

        $self->log->debug("b.date: " . $booking_obj->date);
        $self->log->debug("b.gender: " . $booking_obj->gender);
        $self->log->debug("b.slot: " . $booking_obj->slot);
        $self->log->debug("b.user_count: " . $booking_obj->user_count);

        # 슬롯이 부족하다면 오류
        do {
            unless ( $booking_obj->slot > 0 ) {
                die "empty booking slot\n";
            }
            unless ( $booking_obj->slot > $booking_obj->user_count ) {
                die "not enough booking slot\n";
            }
        };

        # 슬롯 시간 이후면 오류
        do {
            my $dt_now = DateTime->now( time_zone => $self->config->{timezone} );
            unless ( $dt_now->epoch < $booking_obj->date->epoch ) {
                die "cannot book past slots\n";
            }
        };

        # 동일 날짜에 예약 내역이 있다면 오류
        do {
            my $dt = $booking_obj->date->clone;
            my $dtf = $self->app->DB->storage->datetime_parser;
            my $rs = $user->search_related(
                "orders",
                {
                    "me.status_id" => {
                        -in => [
                            $OpenCloset::Constants::Status::RESERVATED, # 방문예약
                            $OpenCloset::Constants::Status::PAYMENT,    # 결제대기
                        ],
                    },
                },
                {
                    join     => "booking",
                    order_by => [
                        { -asc => "booking.date" },
                        { -asc => "me.id" },
                    ],
                },
            )->search_literal(
                "DATE_FORMAT(`booking`.`date`, '%Y-%m-%d') = ?",
                $dt->ymd,
            );

            my @orders = $rs->all;
            if (@orders) {
                for my $order (@orders) {
                    $self->log->debug( "  order: " . $order->id );
                }
                die "prohibit same day booking\n";
            }
        };

        # 사용자 정보 갱신
        do {
            my %user_params;
            my %user_info_params;

            #
            # id
            #
            $user_params{id} = $user->id;

            #
            # email & birth
            #
            $user_params{email}      = $v->param("email") unless $user->email;
            $user_info_params{birth} = $v->param("birth") unless $user_info->birth;

            #
            # prefer_category
            #
            {
                my $col     = "pre_category";
                my $param   = "prefer_category";
                my $col_val = $user_info->get_column($col);
                next if $col_val && $col_val eq $v->param($param);
                $user_info_params{$col} = $self->prefer_category_to_string( $v->every_param($param) );
            }

            #
            # others
            #
            my @ui_items = (
                { col => "address1",    param => "address1" },
                { col => "address2",    param => "address2" },
                { col => "address3",    param => "address3" },
                { col => "address4",    param => "address4" },
                { col => "wearon_date", param => "wear_ymd" },
                { col => "purpose",     param => "purpose" },
                { col => "purpose2",    param => "purpose2" },
                { col => "pre_color",   param => "prefer_color" },
                { col => "pre_style",   param => "prefer_style" },
            );
            for my $item (@ui_items) {
                my $col_val = $user_info->get_column($item->{col});
                next if $col_val && $col_val eq $v->param($item->{param});
                $user_info_params{$item->{col}} = $v->param($item->{param});
            }

            $user = $self->update_user( \%user_params, \%user_info_params );
        };

        # 예약
        my $order_api = OpenCloset::API::Order->new(
            schema      => $self->app->DB,
            monitor_uri => $self->config->{monitor_uri},
        );
        my $order_obj;
        my %extra;
        my ($stderr) = Capture::Tiny::capture_stderr {
            $order_obj = $order_api->reservated( $user, $booking_obj->date, %extra );
        };
        $self->log->warn("reservated error: $stderr");

        #
        # 주문서도 동시에 갱신시킴
        #
        {
            my $agent = $v->param("wear_self") eq "other" ? 1 : 0;
            my $wearon_date = DateTime::Format::Strptime->new(
                pattern   => q{%F},
                time_zone => $self->config->{timezone},
            )->parse_datetime( $v->param("wear_ymd") );

            $order_obj->update(
                {
                    agent        => $agent,
                    purpose      => $v->param("purpose"),
                    purpose2     => $v->param("purpose2"),
                    pre_category => $self->prefer_category_to_string( $v->every_param("prefer_category") ),
                    pre_color    => $v->param("prefer_color"),
                    pre_style    => $v->param("prefer_style"),
                    wearon_date  => $wearon_date,
                },
            );
        }

        $guard->commit;

        $data{user} = $self->app->flatten_user($user);
        $data{order} = { id => $order_obj->id };
        ( 1, undef );
    }
    Try::Tiny::catch {
        chomp;
        my $err = $_;
        return ( undef, $err );
    };
    unless ($success) {
        my $msg = "$error";
        $self->error( 500, { str => $msg, data => {}, } );
        return;
    }

    #$self->render( json => \%data );

    #
    # response
    #
    $self->res->headers->header(
        "Location" => $self->url_for( "/api/order/" . $data->{order}{id} ),
    );
    $self->respond_to( json => { status => 201, json => \%data } );
}

=head2 api_cancel_order

    DELETE /api/order/:order_id/booking

=cut

sub api_cancel_order ($self) {
    #
    # fetch params
    #
    my %params = $self->get_params(qw/ order_id /);

    #
    # validate params
    #
    my $v = $self->app->validator->validation->input(\%params);
    $v->required("order_id")->obj_id;
    my @invalid_fields;
    my @fields = qw(
        order_id
    );
    for my $field (@fields) {
        push @invalid_fields, $field if $v->has_error($field);
    }
    if ( $v->has_error ) {
        my $msg = "invalid params: " . join(", ", @invalid_fields);
        $self->error( 400, { str => $msg, data => {} } );
        return;
    }

    my $order   = $self->app->DB->resultset("Order")->find( $params{order_id} );
    my $booking = $order->booking;

    $self->app->log->debug("order.id: " . $order->id);
    $self->app->log->debug("booking.id: " . $booking->id);

    my %data = (
        order_id   => $order->id,
        booking_id => $booking->id,
    );

    #
    # check fail condition
    #
    # 이미 OpenCloset::API::Order->cancel($order) API는 지우기 전에 상태를
    # 확인하지만, 실제로 지울 수 있는 조건은 상황에 따라 달라질 수 있으므로
    # 조건 별 확인은 호출하는 쪽에서 진행하는 것이 적절할 것으로 보입니다.
    #
    # 현재 방문 예약을 취소하는 경우는 다음과 같습니다.
    #
    # - 방문 예약인 경우 (API 내부에서 수행하므로 중복 체크)
    # - 방문 예약 일시가 지나지 않은 경우
    #
    {
        my $status_name = $order->status->name;
        unless ( $status_name eq "방문예약" ) {
            my $msg = "invalid order.status: order($data{order_id}), status($status_name)";
            $self->error( 400, { str => $msg, data => \%data } );
        }
        my $dt_now     = DateTime->now( time_zone => $self->config->{timezone} );
        my $dt_booking = $booking->date;
        if ( $booking->date < $dt_now ) {
            my $msg = "invalid order.booking.date: order($data{order_id}), booking($data{booking_id}), $dt_booking > $dt_now";
            $self->error( 400, { str => $msg, data => \%data } );
            return;
        }
    }

    #
    # cancel the order
    #
    # 또한 지금은 주문서를 지우지만 원래의 예전 코드는 주문서를 지우지
    # 않았습니다. 지우기보다는 예약 정보만 제거하고, 주문서 상태를 남겨둔다면
    # 예약 진행 중 취소하는 비율과 같은 유의미한 통계를 확보할 수도 있습니다.
    # 변경된 기존 코드와 최대한 유사하게 동작하기 위해 동일한 API로 주문서를
    # 제거합니다.
    #
    my $order_api = OpenCloset::API::Order->new(
        schema      => $self->app->DB,
        monitor_uri => $self->config->{monitor_uri},
    );
    my $ret = $order_api->cancel($order);
    if (!$ret) {
        my $msg = "failed to cancel order: order($data{order_id}), booking($data{booking_id})";
        $self->error( 500, { str => $msg, data => \%data } );
    }

    $self->respond_to( json => { status => 200, json => \%data } );
}

1;
