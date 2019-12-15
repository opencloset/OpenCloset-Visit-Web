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

1;
