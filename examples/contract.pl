#!/usr/bin/env perl

use strict;
use warnings;

use AnyEvent;
use Getopt::Long;

use lib '/home/uwe/repos/protocol-tws/lib';
use Protocol::TWS;

use lib '/home/uwe/repos/anyevent-tws/lib';
use AnyEvent::TWS;


my %TYPES = (
    STK => \&print_stock,
    OPT => \&print_option,
);


my %contract = (
    conId    => '',
    symbol   => '',
    secType  => 'STK',
    expiry   => '',
    strike   => '',
    right    => '',
    exchange => 'SMART',
    currency => 'USD',
);


my $result = GetOptions(
    "conId|i=s"    => \$contract{conId},
    "symbol|s=s"   => \$contract{symbol},
    "secType|t=s"  => \$contract{secType},
    "expiry|e=s"   => \$contract{expiry},
    "strike|st=s"  => \$contract{strike},
    "right|r=s"    => \$contract{right},
    "exchange|e=s" => \$contract{exchange},
    "currency|c=s" => \$contract{currency},
);


my $tws = AnyEvent::TWS->new(
    host => $ENV{TWS_HOST},
    port => $ENV{TWS_PORT},
);

$tws->connect->recv;

my $cv = AE::cv;

my $request = Protocol::TWS::Request::reqContractDetails->new(
    id       => 1,
    contract => Protocol::TWS::Struct::Contract->new(%contract),
);
$tws->call($request, \&print_contract);

$cv->recv;

sub print_contract {
    my ($response) = @_;

    if ($response->_name eq 'contractDetailsEnd') {
        return $cv->send;
    }

    my $contract = $response->contractDetails->summary;
    my $code = $TYPES{$contract->secType}
        or die 'Unknown secType ' . $contract->secType;

    $code->($contract);
}

sub print_stock {
    my ($contract) = @_;

    printf "conId:  %s\n", $contract->conId;
    printf "symbol: %s\n", $contract->symbol;

    print "\n";
}

sub print_option {
    my ($contract) = @_;

    printf "conId:  %s\n", $contract->conId;
    printf "symbol: %s\n", $contract->symbol;
    printf "expiry: %s\n", $contract->expiry;
    printf "strike: %s\n", $contract->strike;
    printf "right:  %s\n", $contract->right;

    print "\n";
}

