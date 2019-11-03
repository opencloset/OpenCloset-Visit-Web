package OpenCloset::Web::Controller::Order;
use Mojo::Base 'Mojolicious::Controller';

use DateTime                   ();
use DateTime::Format::Strptime ();

use OpenCloset::API::Order;

has api_order => sub {
    my $self = shift;

    my $obj = OpenCloset::API::Order->new(
        schema      => $self->app->DB,
        monitor_uri => $self->config->{monitor_uri},
    );

    return $obj;
};

## Day of week map
my %DOW_MAP = (
    1 => '월',
    2 => '화',
    3 => '수',
    4 => '목',
    5 => '금',
    6 => '토',
    7 => '일',
);

=head1 METHODS

=head2 auth

    under /order/:id

=cut

sub auth {
    my $self  = shift;
    my $id    = $self->param('id');
    my $phone = $self->param('phone') || '';

    my $order = $self->app->DB->resultset('Order')->find( { id => $id } );
    unless ($order) {
        $self->error(
            404, { str => "주문서를 찾을 수 없습니다: $id" },
            'error/not_found'
        );
        return;
    }

    unless ($phone) {
        $self->error(
            400, { str => "본인확인을 할 수 없습니다." },
            'error/bad_request'
        );
        return;
    }

    if ( $order->status_id != 14 ) {
        $self->error(
            400,
            { str => "방문예약 상태의 주문서만 변경/취소할 수 있습니다." },
            'error/bad_request'
        );
        return;
    }

    my $user      = $order->user;
    my $user_info = $user->user_info;

    unless ( $user_info->gender ) {
        $self->error(
            400, { str => "성별을 확인할 수 없습니다." },
            'error/bad_request'
        );
        return;
    }

    if ( substr( $user_info->phone, -4 ) ne $phone ) {
        $self->error(
            400,
            { str => "대여자의 휴대폰번호와 일치하지 않습니다." },
            'error/bad_request'
        );
        return;
    }

    my $booking = $order->booking;
    unless ( $booking and $booking->date ) {
        $self->error(
            400, { str => "예약시간이 비어있습니다." },
            'error/bad_request'
        );
        return;
    }

    ## 예약일이 이미 지난날이면 아니됨 최대 오늘까지
    my $today = DateTime->today( time_zone => $self->config->{timezone} );
    my $booking_day = $booking->date->clone->truncate( to => 'day' );
    if ( $today->epoch - $booking_day->epoch > 0 ) {
        $self->error(
            400,
            { str => "예약시간이 지났습니다. 다시 방문예약을 해주세요." },
            'error/bad_request'
        );
        return;
    }

    $self->stash(
        order     => $order,
        user      => $user,
        user_info => $user_info,
        booking   => $booking
    );

    return 1;
}

=head2 booking

    GET /order/:id/booking/edit

=cut

sub booking {
    my $self         = shift;
    my $user_info    = $self->stash('user_info');
    my @booking_list = $self->booking_list( $user_info->gender );
    return unless @booking_list;

    my $pattern = '%Y-%m-%d';
    my $strp    = DateTime::Format::Strptime->new(
        pattern   => $pattern,
        time_zone => $self->config->{timezone},
        on_error  => 'undef',
    );

    my %dateby;
    for my $row (@booking_list) {
        my $ymd = substr $row->{date}, 0,  10;
        my $hm  = substr $row->{date}, -8, 5;

        my $dt  = $strp->parse_datetime($ymd);
        my $dow = $dt->day_of_week;
        if ( $row->{slot} - $row->{user_count} ) {
            $row->{date_str} = sprintf "%s (%s요일) %s %d명 예약 가능", $ymd,
                $DOW_MAP{$dow}, $hm, $row->{slot} - $row->{user_count};
        }
        else {
            $row->{date_str} = sprintf "%s (%s요일) %s 예약 인원 초과", $ymd,
                $DOW_MAP{$dow}, $hm;
        }

        push @{ $dateby{$ymd} }, $row;
    }

    $self->render( booking_list => \%dateby );
}

=head2 update_booking

    PUT /order/:id/booking

=cut

sub update_booking {
    my $self  = shift;
    my $order = $self->stash('order');

    my $v = $self->validation;
    $v->required('booking_id');

    return $self->error( 400, { str => 'booking_id is required' }, 'error/bad_request' )
        if $v->has_error;

    my $booking_id = $v->param('booking_id');
    my $booking    = $self->app->DB->resultset('Booking')->find( { id => $booking_id } );
    my $success    = $self->api_order->update_reservated( $order, $booking->date );
    my $message =
        $success
        ? '예약시간이 변경되었습니다.'
        : '예약시간을 변경하지 못했습니다.';
    $self->flash( alert => $message );
    $self->render( json => $self->flatten_booking( $order->booking ) );
}

=head2 cancel_form

    GET /order/:id/cancel?phone=xxxx

=cut

sub cancel_form {
    my $self    = shift;
    my $booking = $self->stash('booking');
    my $dow     = $booking->date->day_of_week;
    $self->render( day_of_week => $DOW_MAP{$dow} );
}

=head2 delete_cors

    OPTIONS /order/:id

=cut

sub delete_cors {
    my $self = shift;

    my $origin = $self->req->headers->header('origin');
    my $method = $self->req->headers->header('access-control-request-method');

    return $self->error( 400, "Not Allowed Origin: $origin" )
        unless $origin =~ m/theopencloset\.net/;

    $self->res->headers->header( 'Access-Control-Allow-Origin'  => $origin );
    $self->res->headers->header( 'Access-Control-Allow-Methods' => 'OPTIONS, DELETE' );
    $self->respond_to( any => { data => '', status => 200 } );
}

=head2 delete

    DELETE /order/:id?phone=xxxx

=cut

sub delete {
    my $self  = shift;
    my $order = $self->stash('order');

    $self->api_order->cancel($order);

    my $origin = $self->req->headers->header('origin');
    $self->res->headers->header( 'Access-Control-Allow-Origin' => $origin );

    $self->render( json => {} );
}

1;
