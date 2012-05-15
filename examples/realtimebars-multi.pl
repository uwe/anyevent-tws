#!/usr/bin/env perl

use strict;
use warnings;

use AnyEvent;

use lib '/home/uwe/repos/protocol-tws/lib';
use Protocol::TWS;

use lib '/home/uwe/repos/anyevent-tws/lib';
use AnyEvent::TWS;


my $tws = AnyEvent::TWS->new(
    host => $ENV{TWS_HOST},
    port => $ENV{TWS_PORT},
);

$tws->connect->recv;

my $contract = Protocol::TWS::Struct::Contract->new(
    symbol   => 'IBM',
    secType  => 'OPT',
    expiry   => '20120720',
    strike   => '200',
    right    => 'PUT',
    exchange => 'SMART',
    currency => 'USD',
);

my $req = Protocol::TWS::Request::reqRealTimeBars->new(
    id         => 1,
    contract   => $contract,
    barSize    => 5,
    whatToShow => '',
    useRTH     => 0,
);

my $cv = AnyEvent->condvar;

my $id = 1;
foreach my $type (qw/TRADES BID ASK MIDPOINT/) {
    $req->id($id++);
    $req->whatToShow($type);
    $tws->call($req, sub { print_bar(shift, $type) });
}

# program should terminate after 60 seconds
my $timer = AnyEvent->timer(
    after => 60,
    cb    => sub { $cv->send },
);

$cv->recv;


sub print_bar {
    my ($res, $type) = @_;

    printf("%9s - %.2f\n", $type, $res->close);
}

