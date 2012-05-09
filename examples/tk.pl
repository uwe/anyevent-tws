#!/usr/bin/env perl

use strict;
use warnings;

use Tk;

use AnyEvent;
use Data::Dumper;

use lib '/home/uwe/repos/protocol-tws/lib';
use Protocol::TWS;

use lib '/home/uwe/repos/anyevent-tws/lib';
use AnyEvent::TWS;


my $tws = AnyEvent::TWS->new(host => '192.168.2.53');


my @schema = (
    [conId    => ''],
    [symbol   => ''],
    [secType  => 'STK'],
    [expiry   => ''],
    [strike   => ''],
    [right    => ''],
    [exchange => 'SMART'],
    [currency => 'USD'],
);


my $mw = MainWindow->new;

my %entry = ();
foreach (@schema) {
    my ($name, $default) = @$_;

    my $frame = $mw->Frame;
    $frame->Label(-text => $name . ':')->pack(-side => 'left');
    $entry{$name} = $frame->Entry(-text => $default)->pack(-side => 'right');
    $frame->pack(-fill => x => -side => 'top');
}

$mw->Button(-text => 'Search', -command => sub { _search($tws, \%entry) })->pack;

MainLoop;

sub _search {
    my ($tws, $entry) = @_;

    my %data = ();
    foreach (@schema) {
        my $name = $_->[0];
        $data{$name} = $entry->{$name}->get;
    }

    $tws->call(
        Protocol::TWS::Request::reqContractDetails->new(
            id       => 1,
            contract => Protocol::TWS::Struct::Contract->new(%data),
        ),
        sub {
            my $res = shift;
            warn Dumper $res;
        },
    );
}

