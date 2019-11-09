#!/usr/bin/env perl

use utf8;
use strict;
use warnings;
use feature qw( say );
use experimental qw( signatures );

binmode STDOUT, ":encoding(UTF-8)";
binmode STDERR, ":encoding(UTF-8)";

use File::ChangeNotify;

my $watcher = File::ChangeNotify->instantiate_watcher(
    directories => [
        qw(
            src/scss
            src/es6
            )
    ],
    filter => qr/\.(?:scss|es6)$/,
);

while ( my @events = $watcher->wait_for_events ) {
    my $is_js  = 0;
    my $is_css = 0;
    for my $event (@events) {
        use experimental qw( switch smartmatch );

        printf "%s - %s\n", $event->path, $event->type;
        given ( $event->path ) {
            ++$is_js when m/\.es6$/;
            ++$is_css when m/\.scss$/;
        }
    }
    if ( $is_js && $is_css ) {
        system(qw/ npm run build /);
    }
    elsif ($is_js) {
        system(qw/ npm run build:js /);
    }
    elsif ($is_css) {
        system(qw/ npm run build:css /);
    }
}
