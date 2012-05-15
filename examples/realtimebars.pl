#!/usr/bin/env perl

use strict;
use warnings;

use AnyEvent;

use lib '/home/uwe/repos/protocol-tws/lib';
use Protocol::TWS;

use lib '/home/uwe/repos/anyevent-tws/lib';
use AnyEvent::TWS;


my $symbol = $ARGV[0] || 'AAPL';

my $tws = AnyEvent::TWS->new(
    host => $ENV{TWS_HOST},
    port => $ENV{TWS_PORT},
);

$tws->connect->recv;

my $contract = Protocol::TWS::Struct::Contract->new(
    symbol   => $symbol,
    secType  => 'STK',
    exchange => 'SMART',
    currency => 'USD',
);

my $req = Protocol::TWS::Request::reqRealTimeBars->new(
    id         => 1,
    contract   => $contract,
    barSize    => 5,
    whatToShow => 'TRADES',
    useRTH     => 0,
);

my $last;
my $ups   = 0;
my $downs = 0;

my $timer;
my $cv = AnyEvent->condvar;

$tws->call(
    $req,
    sub {
        my ($res) = @_;

        # initialize with first bar
        unless ($last) {
            $last = $res->wap;
            return;
        }

        # up or down since last bar?
        if ($res->wap > $last) {
            $ups++;
        }
        elsif ($res->wap < $last) {
            $downs++;
        }
        $last = $res->wap;

        printf("%.2f (+%3d) (-%3d)\n", $res->wap, $ups, $downs);

        # wait for some periods
        return unless $ups + $downs > 10;
        
        # do something (silly) with up/down count
        if ($ups > 2 * $downs) {
            print "I would buy ($last).\n";
            $ups = $downs = 0;
        }
        elsif ($downs > 2 * $ups) {
            print "I would sell ($last).\n";
            $ups = $downs = 0;
        }

        # quit after 50 bars without "action"
        if ($ups + $downs > 50) {
            $tws->call(
                Protocol::TWS::Request::cancelRealTimeBars->new(id => 1),
                sub {},
            );

            # exit program after some seconds
            $timer = AnyEvent->timer(
                after => 5,
                cb    => sub { $cv->send },
            );
        }
    },
);

$cv->recv;

