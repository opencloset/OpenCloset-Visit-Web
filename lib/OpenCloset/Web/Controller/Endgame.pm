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
    my $reserved_list = [
        {
            order_id     => 29182,
            booking_ymd  => "2019-07-05",
            booking_hms  => "09:30",
            wear_self    => "1",
            wear_gender  => "male",
            wear_date    => "2019-07-07",
            prefer_style => "basic",
            prefer_color => "navy",
            purpose      => "졸업(입학)식",
            address1     => "서울시 광진구 구의동",
            address2     => "35-23 201호",
        },
        {
            order_id     => 29192,
            booking_ymd  => "2019-07-09",
            booking_hms  => "12:00",
            wear_self    => "0",
            wear_gender  => "male",
            wear_date    => "2019-07-09",
            prefer_style => "basic",
            prefer_color => "navy",
            purpose      => "면접",
            address1     => "서울시 광진구 구의동",
            address2     => "35-23 201호",
        },
    ];
    $self->stash( reserved_list => $reserved_list );
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
    my $order_id = $self->param("order_id");

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
        $self->error( 400, { str => $msg, data => {}, } );
        return;
    }

    my $order = $self->app->DB->resultset("Order")->find($order_id);
    my $booking = $order->booking;
    my $user = $order->user;
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
