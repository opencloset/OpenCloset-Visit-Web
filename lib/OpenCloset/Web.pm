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
        bg_image    => [],
        header      => 1,
        footer      => 1,
        back_link   => q{},
        alert       => q{},
        type        => q{},
        %{ $self->plugin('Config') }
    );

    $self->plugin('validator');
    $self->plugin('OpenCloset::Plugin::Helpers');
    $self->plugin('OpenCloset::Web::Plugin::Helpers');

    $self->_authentication;
    $self->_public_routes;
    $self->_endgame_routes;
    $self->_hooks;

    $self->secrets( $self->defaults->{secrets} );
    $self->sessions->cookie_domain( $self->defaults->{cookie_domain} );
    $self->sessions->cookie_name('opencloset');
    $self->sessions->default_expiration(86400);

    push @{ $self->commands->namespaces }, 'OpenCloset::Web::Command';

    $self->app->log->info("restarted...");
}

=head2 _authentication

=cut

sub _authentication {
    my $self = shift;

    $self->plugin(
        'authentication' => {
            autoload_user => 1,
            load_user     => sub {
                my ( $app, $uid ) = @_;

                my $user_obj = $self->DB->resultset('User')->find( { id => $uid } );

                return $user_obj;
            },
            session_key   => 'access_token',
            validate_user => sub {
                my ( $self, $user, $pass, $extradata ) = @_;

                my $user_obj = $self->DB->resultset('User')->find( { email => $user } );
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
                    $self->log->warn("$user\'s password is expired");
                    return;
                }

                unless ( $user_obj->check_password($pass) ) {
                    $self->log->warn("$user\'s password is wrong");
                    return;
                }

                return $user_obj->id;
            },
        }
    );
}

=head2 _public_routes

=cut

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

    ## common public routes
    $r->options('/api/postcode/search')->to('API#api_postcode_preflight_cors');
    $r->get('/api/postcode/search')->to('API#api_postcode_search');

    my $api = $r->under('/api')->to('user#auth');
    $api->post('/sms/validation')->to('API#api_create_sms_validation');
    $api->get('/gui/booking-list')->to('API#api_gui_booking_list');
}

=head2 _endgame_routes

=cut

sub _endgame_routes {
    my $self = shift;
    my $r    = $self->routes;

    $r->get( "/", sub ($c) { $c->redirect_to( $c->url_for("/endgame/offintro") ); } );

    my $endgame = $r->under('/endgame');
    $endgame->get("/offintro")->to("endgame#offintro");
    $endgame->get("/offmain")->to("endgame#offmain");
    $endgame->get("/offcert")->to("endgame#offcert");
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
