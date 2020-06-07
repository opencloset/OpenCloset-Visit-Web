package OpenCloset::Web::Controller::Auth;
use Mojo::Base "Mojolicious::Controller";

use DateTime ();

=head1 METHODS

=head2 email

=cut

sub email {
    my $self = shift;

    #
    # validate parameter
    #
    my $v = $self->validation;

    $v->required("email")->email;
    $v->required("password")->size( 8, undef );

    my @invalid_fields;
    my @fields = qw(
        email
        password
    );
    for my $field (@fields) {
        push @invalid_fields, $field if $v->has_error($field);
    }

    # Check if validation is failed
    if ( $v->has_error ) {
        $self->logout if $self->is_user_authenticated; # logout if already logged in
        my $msg = "invalid params: " . join(", ", @invalid_fields);
        $self->error( 400, { str => $msg, data => {}, } );
        return;
    }

    my $email    = $v->param("email");
    my $password = $v->param("password");
    unless ( $self->authenticate( $email, $password ) ) {
        $self->logout if $self->is_user_authenticated; # logout if already logged in
        my $msg = "authenticate failed";
        $self->error( 401, { str => $msg, data => {}, } );
        return;
    }

    $self->log->info("email login: $email");

    #
    # response
    #
    my $user_obj = $self->current_user;
    my $data = $self->app->flatten_user($user_obj);
    $self->respond_to( json => { status => 200, json => $data } );
}

=head2 phone

=cut

sub phone {
    my $self = shift;

    #
    # validate parameter
    #
    my $v = $self->validation;

    $v->required("phone")->phone;
    $v->required("sms")->int->size( 6, 10 );
    $v->required("gender")->in( "male", "female" );
    $v->required("name")->size( 2, undef );

    my @invalid_fields;
    my @fields = qw(
        phone
        sms
        gender
        name
    );
    for my $field (@fields) {
        push @invalid_fields, $field if $v->has_error($field);
    }

    # Check if validation is failed
    if ( $v->has_error ) {
        $self->logout if $self->is_user_authenticated; # logout if already logged in
        my $msg = "invalid params: " . join(", ", @invalid_fields);
        $self->error( 400, { str => $msg, data => {}, } );
        return;
    }

    my $phone     = $v->param("phone");
    my $sms       = $v->param("sms");
    my %extradata = (
        type => "phone",
        opts => {
            name   => $v->param("name"),
            gender => $v->param("gender"),
        }
    );
    unless ( $self->authenticate( $phone, $sms, \%extradata ) ) {
        $self->logout if $self->is_user_authenticated; # logout if already logged in
        my $msg = "authenticate failed";
        $self->error( 401, { str => $msg, data => {}, } );
        return;
    }

    $self->log->info("phone login: $phone");

    #
    # response
    #
    my $user_obj = $self->current_user;
    my $data = $self->app->flatten_user($user_obj);
    $self->respond_to( json => { status => 200, json => $data } );
}

=head2 loggedin

=cut

sub loggedin {
    my $self = shift;

    # check: token from http header
    my $token_header;
    # ...

    # check: token from user param
    my $token_param;
    # ...

    # check: session
    my $session = $self->is_user_authenticated;

    unless ( $token_header || $token_param || $session ) {
        my $msg = "authenticate failed";
        $self->error( 401, { str => $msg, data => {}, } );
        return;
    }

    my $user_obj = $self->current_user;
    $self->log->info( "logged-in user: " . $user_obj->email );
    $self->stash(
        user => $user_obj,
    );

    return 1;
}

=head2 whoami

=cut

sub whoami {
    my $self = shift;

    #
    # response
    #
    my $user_obj = $self->current_user;
    my $data = $self->app->flatten_user($user_obj);
    $self->respond_to( json => { status => 200, json => $data } );
}

=head2 auth_logout

=cut

sub auth_logout {
    my $self = shift;

    #
    # validate parameter
    #
    my $v = $self->validation;

    $v->optional("return_url")->http_url;

    my @invalid_fields;
    my @fields = qw(
        return_url
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

    my $return_url = $v->param("return_url");

    #
    # response
    #
    my $user_obj = $self->current_user;
    my $email = $user_obj->email;
    $self->logout;
    $self->log->info("logout: $email");
    if ($return_url) {
        $self->redirect_to($return_url);
        return;
    }
    my $data = {
        email => $email,
        msg   => "logged out",
    };
    $self->respond_to( json => { status => 200, json => $data } );
}

1;
