#!/usr/bin/env perl

# request historical quotes

use strict;
use warnings;

use AnyEvent;
use AnyEvent::TWS;
use DateTime;


my $tws = AnyEvent::TWS->new(
    host => $ENV{TWS_HOST},
    port => $ENV{TWS_PORT},
);

$tws->connect->recv;

my $contract = $tws->struct(Contract => {
    symbol      => 'EUR',
    secType     => 'CASH',
    exchange    => 'IDEALPRO',
    localSymbol => 'EUR.USD',
});

# yesterday (Friday on weekends)
my $date = DateTime->today->subtract(days => 1);
$date = $date->subtract(days => $date->dow - 5) if $date->dow > 5;

my $request = $tws->request(reqHistoricalData => {
    id             => $tws->next_valid_id,
    contract       => $contract,
    endDateTime    => $date->ymd('') . '  23:00:00',
    durationStr    => '1 D',
    barSizeSetting => '1 hour',
    whatToShow     => 'BID_ASK',
    useRTH         => 0,
    formatDate     => 1,
});

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

