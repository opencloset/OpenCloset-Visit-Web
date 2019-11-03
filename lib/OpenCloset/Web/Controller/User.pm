package OpenCloset::Web::Controller::User;
use Mojo::Base 'Mojolicious::Controller';

use DateTime ();

=head1 METHODS

=head2 auth

    # except public routes
    under /

=cut

sub auth {
    my $self = shift;

    if ( $self->is_user_authenticated ) {
        my $user      = $self->current_user;
        my $user_info = $user->user_info;
        return 1 if $user_info->staff;

        my $email = $user->email;
        $self->log->warn("oops! $email is not a staff");
    }

    my $req_path = $self->req->url->path;
    return 1 if $req_path =~ m{^/api/sms/validation(\.json)?$};
    return 1 if $req_path =~ m{^/api/postcode/search(\.json)?$};
    return 1 if $req_path =~ m{^/api/search/user(\.json)?$};

    if ( $req_path =~ m{^/api/gui/booking-list(\.json)?$} ) {
        my $phone = $self->param('phone');
        my $sms   = $self->param('sms');

        $self->error( 400, { data => { error => 'missing phone' } } ), return
            unless defined $phone;
        $self->error( 400, { data => { error => 'missing sms' } } ), return
            unless defined $sms;

        #
        # find user
        #
        my @users = $self->app->DB->resultset('User')
            ->search( { 'user_info.phone' => $phone }, { join => 'user_info' }, );
        my $user = shift @users;
        $self->error( 400, { data => { error => 'user not found' } } ), return unless $user;

        #
        # GitHub #199 - check expires
        #
        my $now = DateTime->now( time_zone => $self->config->{timezone} )->epoch;
        $self->error( 400, { data => { error => 'expiration is not set' } } ), return
            unless $user->expires;
        $self->error( 400, { data => { error => 'sms is expired' } } ), return
            unless $user->expires > $now;
        $self->error( 400, { data => { error => 'sms is wrong' } } ), return
            if $sms ne $user->authcode;

        return 1;
    }
    elsif ($req_path =~ m{^/api/search/sms(\.json)?$}
        || $req_path =~ m{^/api/sms/\d+(\.json)?$} )
    {
        my $email    = $self->param('email');
        my $password = $self->param('password');

        $self->error( 400, { data => { error => 'missing email' } } ), return
            unless defined $email;
        $self->error( 400, { data => { error => 'missing password' } } ), return
            unless defined $password;
        $self->error( 400, { data => { error => 'password is wrong' } } ), return
            unless $self->authenticate( $email, $password );

        return 1;
    }
    $self->app->log->debug("ua: 5");

    $self->respond_to(
        json => { json => { error => 'invalid_access' }, status => 400 },
        html => sub { $self->redirect_to( $self->url_for('/visit') ); }
    );

    return;
}

1;
