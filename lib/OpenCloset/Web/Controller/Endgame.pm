package OpenCloset::Web::Controller::Endgame;
use Mojo::Base 'Mojolicious::Controller';

use experimental qw( signatures );

=head1 METHODS

=head2 offintro

    GET /endgame/offintro

=cut

sub offintro ($self) {
}

=head2 offmain

    GET /endgame/offmain

=cut

sub offmain ($self) {
}

=head2 offcert

    GET /endgame/offcert

=cut

sub offcert ($self) {
    $self->logout if $self->is_user_authenticated; # logout if already logged in
}

=head2 offlist

    GET /endgame/offlist

=cut

sub offlist ($self) {
    my $current_user = $self->stash("user");

    my $now      = DateTime->now( time_zone => $self->config->{timezone} );
    my $dtf      = $self->app->DB->storage->datetime_parser;
    my $order_rs = $current_user->orders->search(
        {
            "booking_id" => { "!=" => undef },
            "booking.date" => { ">" => $dtf->format_datetime($now) },
            "status.name" => "방문예약",
        },
        {
            join => [
                "booking",
                "status",
            ],
            prefetch => [
                "booking",
                "status",
                { "user" => "user_info" },
            ],
            order_by => [
                { -desc => "booking.date" },
            ],
        },
    );

    my @reserved_list;
    while ( my $order = $order_rs->next ) {
        # wearon_date could be undefined
        my $wearon_date = $order->wearon_date;
        push(
            @reserved_list,
            {
                order_id     => $order->id,
                booking_ymd  => $order->booking->date->ymd,
                booking_hms  => $order->booking->date->strftime("%H:%M"),
                wear_self    => !$order->agent,
                wear_gender  => $order->booking->gender,
                wear_date    => $wearon_date ? $wearon_date->ymd : q{},
                prefer_style => $order->pre_style,
                prefer_color => $order->pre_color,
                purpose      => $order->purpose,
                address1     => $order->user->user_info->address3,
                address2     => $order->user->user_info->address4,
            },
        );
    }

    $self->stash( reserved_list => \@reserved_list );
}

=head2 offdate

    GET /endgame/offdate

=cut

sub offdate ($self) {
}

=head2 offorder1

    GET /endgame/offorder1

=cut

sub offorder1 ($self) {
}

=head2 offorder2

    GET /endgame/offorder2

=cut

sub offorder2 ($self) {
}

=head2 offuser

    GET /endgame/offorder2

=cut

sub offuser ($self) {
}

=head2 offbooked

    GET /endgame/offbooked

=cut

sub offbooked ($self) {
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

    my $order_id  = $v->param("order_id");
    my $order     = $self->app->DB->resultset("Order")->find($order_id);
    my $booking   = $order->booking;
    my $user      = $order->user;
    my $user_info = $user->user_info;

    my $current_user = $self->stash("user");
    unless ( $current_user->id == $user->id ) {
        my $msg = sprintf( "invalid order.user.id: %d != %d", $current_user->id, $user->id );
        $self->error( 401, { str => $msg, data => {} } );
        return;
    }

    $self->stash(
        order_id        => $order_id,
        booking_date    => $booking->date->strftime('%Y-%m-%d %H:%M'),
        user_name       => $user->name,
        user_info_phone => $user_info->phone,
    );
}

1;
