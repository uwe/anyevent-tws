#!/usr/bin/env perl

use strict;
use warnings;

use AnyEvent;
use Getopt::Long;

use lib '/home/uwe/repos/protocol-tws/lib';
use Protocol::TWS;

use lib 'lib';
use AnyEvent::TWS;


my $symbol   = '';
my $sec_type = 'STK';
my $expiry   = '';
my $strike   = '';
my $right    = '';
my $exchange = 'SMART';
my $currency = 'USD';


my $result = GetOptions(
    "symbol|s=s"   => \$symbol,
    "sec_type|t=s" => \$sec_type,
    "expiry|e=s"   => \$expiry,
    "strike|st=s"  => \$strike,
    "right|r=s"    => \$right,
    "exchange|e=s" => \$exchange,
    "currency|c=s" => \$currency,
);


my $tws = AnyEvent::TWS->new(host => '192.168.2.53');

my $cv = AE::cv;

my $contract = Protocol::TWS::Struct::Contract->new(
    symbol   => $symbol,
    secType  => $sec_type,
    expiry   => $expiry,
    strike   => $strike,
    right    => $right,
    exchange => $exchange,
    currency => $currency,
);
my $request = Protocol::TWS::Request::reqContractDetails->new(
    id       => 1,
    contract => $contract,
);
$tws->call($request, \&print_contract);

$cv->recv;

sub print_contract {
    my ($response) = @_;

    if ($response->_name eq 'contractDetailsEnd') {
        return $cv->send;
    }

    use Data::Dumper;

    print Dumper $response;
    print "\n";
}

