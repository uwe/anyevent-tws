#!/usr/bin/env perl

BEGIN {
    $ENV{AE_STRICT}  = 1;
    $ENV{AE_VERBOSE} ||= 5;
}

use strict;
use warnings;
use feature qw/say/;

use AnyEvent;
use Data::Dumper;

use lib '/home/uwe/repos/anyevent-tws/lib';
use AnyEvent::TWS;

use lib '/home/uwe/repos/protocol-tws/lib';
use Protocol::TWS;


my $tws = AnyEvent::TWS->new(
    host => $ENV{TWS_HOST},
    port => $ENV{TWS_PORT},
);

$tws->connect->recv;

say 'Accounts: ' . join(', ', @{$tws->{accounts}});

$tws->call(Protocol::TWS::Request::reqCurrentTime->new, sub { say "time: " . (shift)->time });

#$tws->call(req_account_updates());

#my $contract = Protocol::TWS::Struct::Contract->new(symbol => 'ZNGA', secType => 'OPT', strike => '9', right => 'C');
#$tws->call(Protocol::TWS::Request::reqContractDetails->new(id => 1, contract => $contract));

#$tws->call(calculate_option_price());

AE::cv->recv;


sub calculate_implied_volatility {
    my $contract = Protocol::TWS::Struct::Contract->new(
        symbol   => 'ZNGA',
        secType  => 'OPT',
        expiry   => '20120518',
        exchange => 'SMART',
        strike   => '9',
        right    => 'C',
    );
    return Protocol::TWS::Request::calculateImpliedVolatility->new(
        id => 2,
        contract => $contract,
        optionPrice => '0.70',
        underPrice  => '8.33',
    );
}

sub calculate_option_price {
    my $contract = Protocol::TWS::Struct::Contract->new(
        symbol   => 'ZNGA',
        secType  => 'OPT',
        expiry   => '20120518',
        exchange => 'SMART',
        strike   => '9',
        right    => 'C',
    );
    return Protocol::TWS::Request::calculateOptionPrice->new(
        id => 2,
        contract   => $contract,
        volatility => '1.5',
        underPrice => '8.33',
    );
}

sub req_account_updates {
    return Protocol::TWS::Request::reqAccountUpdates->new(
        subscribe => 1,
        acctCode  => '',
    ), sub { say Dumper(shift) };
}

