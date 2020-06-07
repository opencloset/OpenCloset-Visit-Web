package OpenCloset::Web;
use Mojo::Base 'Mojolicious';
use experimental qw( signatures );

use version; our $VERSION = qv("v1.12.11");

use DateTime;

use OpenCloset::Schema;
use OpenCloset::DB::Plugin::Order::Sale;

has DB => sub {
    my $self = shift;

    state $_db;

    my $conf = $self->config->{database};

    unless ($_db) {
        $_db = OpenCloset::Schema->connect(
            {
                dsn      => $conf->{dsn},
                user     => $conf->{user},
                password => $conf->{pass},
                %{ $conf->{opts} },
            }
        );
    }

    return $_db;
};

=head1 METHODS

=head2 startup

This method will run once at server start

=cut

sub startup {
    my $self = shift;

    $self->defaults(
        jses        => [],
        csses       => [],
        bg_image    => q{},
        header      => 1,
        footer      => 1,
        back_link   => q{},
        alert       => q{},
        type        => q{},
        %{ $self->plugin('Config') }
    );

    $self->plugin('OpenCloset::Plugin::Helpers');
    $self->plugin('OpenCloset::Web::Plugin::Helpers');

    $self->_validator;
    $self->_authentication;
    $self->_public_routes;
    $self->_private_routes;
    $self->_endgame_routes;
    $self->_hooks;

    $self->secrets( $self->defaults->{secrets} );
    $self->sessions->cookie_domain( $self->defaults->{cookie_domain} );
    $self->sessions->cookie_name('opencloset');
    $self->sessions->default_expiration(86400);

    push @{ $self->commands->namespaces }, 'OpenCloset::Web::Command';

    $self->app->log->info("restarted...");
}

sub _validator {
    my $self = shift;

    $self->plugin("validator");
    $self->plugin("AdditionalValidationChecks");
}

sub _authentication {
    my $self = shift;

    $self->plugin(
        "authentication" => {
            autoload_user => 1,
            load_user     => sub {
                my ( $app, $uid ) = @_;

                my $user_obj = $self->app->DB->resultset("User")->find( { id => $uid } );

                return $user_obj;
            },
            session_key   => "access_token",
            validate_user => sub {
                my ( $self, $user, $pass, $extradata ) = @_;

                my $user_obj;
                if ( $extradata && ref($extradata) eq "HASH" && %$extradata ) {
                    use experimental qw( smartmatch switch );
                    given ( $extradata->{type} ) {
                        when ("phone") {
                            # phone login
                            my $phone  = $user;
                            my $sms    = $pass;
                            my $name   = $extradata->{opts}{name};
                            my $gender = $extradata->{opts}{gender};

                            #
                            # find user
                            #
                            $user_obj = $self->app->DB->resultset("User")->search(
                                {
                                    "me.name"          => $name,
                                    "user_info.phone"  => $phone,
                                    "user_info.gender" => $gender,
                                },
                                {
                                    join     => "user_info",
                                    prefetch => "user_info",
                                },
                            )->first;
                            unless ($user_obj) {
                                $self->log->warn("cannot find such user: $phone, $name, $gender");
                                return;
                            }
                            unless ( $user_obj->user_info ) {
                                $self->log->warn("user_info not found: $phone, $name, $gender");
                                return;
                            }

                            #
                            # validate code
                            #
                            my $now = DateTime->now( time_zone => $self->config->{timezone} )->epoch;
                            unless ( $user_obj->expires && $user_obj->expires > $now ) {
                                $self->log->warn( "authcode is expired: " . $user_obj->email );
                                return;
                            }
                            if ( $user_obj->authcode ne $sms ) {
                                $self->log->warn( "authcode is wrong: " . $user_obj->email );
                                return;
                            }

                            #
                            # expire the user.expires
                            #
                            $user_obj->update( { expires => $now } );
                        }
                        default {
                            # not supported
                            $self->log->warn( "not supported auth type: " . $extradata->{type} || "N/A" );
                            return;
                        }
                    }
                }
                else {
                    # email login
                    $user_obj = $self->app->DB->resultset("User")->find( { email => $user } );
                    unless ($user_obj) {
                        $self->log->warn("cannot find such user: $user");
                        return;
                    }

                    #
                    # GitHub #199
                    #
                    # check expires when login
                    #
                    my $now = DateTime->now( time_zone => $self->config->{timezone} )->epoch;
                    unless ( $user_obj->expires && $user_obj->expires > $now ) {
                        $self->log->warn("password is expired: $user");
                        return;
                    }

                    unless ( $user_obj->check_password($pass) ) {
                        $self->log->warn("password is wrong: $user");
                        return;
                    }
                }

                return $user_obj->id;
            },
        }
    );
}

sub _public_routes {
    my $self = shift;
    my $r    = $self->routes;

    $r->any('/visit')->to('booking#visit');

    ## easy cancel order and update booking.date
    my $auth = $r->under('/order/:id')->to('order#auth');
    $auth->get('/cancel')->to('order#cancel_form');
    $auth->options('/')->to('order#delete_cors');
    $auth->delete('/')->to('order#delete');
    $auth->get('/booking/edit')->to('order#booking');
    $auth->put('/booking')->to('order#update_booking');

    ## auth public routes
    $r->post("/login/email")->to("Auth#email");
    $r->post("/login/phone")->to("Auth#phone");

    ## common public routes
    $r->options('/api/postcode/search')->to('API#api_postcode_preflight_cors');
    $r->get('/api/postcode/search')->to('API#api_postcode_search');

    my $api = $r->under('/api')->to('user#auth');
    $api->post('/sms/validation')->to('API#api_create_sms_validation');
    $api->get('/gui/booking-list')->to('API#api_gui_booking_list');
}

sub _private_routes {
    my $self = shift;
    my $r    = $self->routes;

    my $auth = $r->under("/")->to("Auth#loggedin");
    $auth->get("/auth/whoami")->to("Auth#whoami");
    $auth->get("/logout")->to("Auth#auth_logout");
}

sub _endgame_routes {
    my $self = shift;
    my $r    = $self->routes;

    $r->get( "/", sub ($c) { $c->redirect_to( $c->url_for("/endgame/offintro") ); } );

    my $endgame = $r->under("/endgame");
    $endgame->get("/offintro")->to("endgame#offintro");
    $endgame->get("/offmain")->to("endgame#offmain");
    $endgame->get("/offcert")->to("endgame#offcert");

    my $auth = $r->under("/endgame")->to("Auth#loggedin");
    $auth->get("/offlist")->to("endgame#offlist");
    $auth->get("/offdate")->to("endgame#offdate");
    $auth->get("/offorder1")->to("endgame#offorder1");
    $auth->get("/offorder2")->to("endgame#offorder2");
    $auth->get("/offuser")->to("endgame#offuser");
    $auth->get("/offbooked")->to("endgame#offbooked");
}

sub _hooks {
    my $self = shift;

    ## Emitted right before the static file server and router start their work.
    ## Very useful for rewriting incoming requests and other preprocessing tasks.
    $self->hook(
        before_dispatch => sub {
            my $c   = shift;
            my $app = $c->app;

            my $domain = $app->config->{cookie_domain};
            my ($host) = split /:/, $c->req->headers->host;
            $app->sessions->cookie_domain( $host =~ m/$domain/ ? $domain : $host );
        }
    );
}

1;
