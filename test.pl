#!/usr/bin/env perl

BEGIN {
    $ENV{AE_STRICT}  = 1;
    $ENV{AE_VERBOSE} = 5;
}

use strict;
use warnings;
use feature qw/say/;

use AnyEvent;

use lib 'lib';
use AnyEvent::TWS;

use lib '/home/uwe/repos/protocol-tws/lib';
use Protocol::TWS;


my $tws = AnyEvent::TWS->new(host => '192.168.2.53');

my $req = Protocol::TWS::Request::reqCurrentTime->new();

$tws->call($req);


AnyEvent->condvar->recv;

