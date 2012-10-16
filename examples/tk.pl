#!/usr/bin/env perl

# very simple example to show that AnyEvent::TWS works in Tk apps too

use strict;
use warnings;

use Tk;

use AnyEvent::TWS;
use Data::Dumper;


my $tws = AnyEvent::TWS->new(
    host => $ENV{TWS_HOST},
    port => $ENV{TWS_PORT},
);

$tws->connect->tws;


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
        $tws->request(reqContractDetails => {
            id       => $tws->next_valid_id,
            contract => $tws->struct(Contract => \%data),
        }),
        sub {
            my $res = shift;
            warn Dumper $res;
        },
    );
}

