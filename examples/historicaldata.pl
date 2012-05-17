#!/usr/bin/env perl

use strict;
use warnings;

use AnyEvent;
use Data::Dumper;

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
    symbol      => 'EUR',
    secType     => 'CASH',
    exchange    => 'IDEALPRO',
    localSymbol => 'EUR.USD',
);

my $request = Protocol::TWS::Request::reqHistoricalData->new(
    id             => 1,
    contract       => $contract,
    endDateTime    => '20120516  23:00:00',
    durationStr    => '1 D',
    barSizeSetting => '1 hour',
    whatToShow     => 'BID_ASK',
    useRTH         => 0,
    formatDate     => 1,
);

$tws->call(
    $request,
    sub {
        my ($response) = @_;

        printf(
            "%-18s | %-7s | %-7s | %-7s | %7s\n",
            'date and time', 'open', 'high', 'low', 'close',
        );
        print "-------------------|---------|---------|---------|---------\n";
        foreach my $bar (@{$response->bars}) {
            printf(
                "%18s | %7.5f | %7.5f | %7.5f | %7.5f\n",
                $bar->date,
                $bar->open,
                $bar->high,
                $bar->low,
                $bar->close,
            );
        }
    },
);

AE::cv->recv;

