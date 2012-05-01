package AnyEvent::TWS;

use strict;
use warnings;
use feature qw/say/;

use AnyEvent;
use AnyEvent::Handle;
use Data::Dumper;

use lib '/home/uwe/repos/protocol-tws/lib';
use Protocol::TWS;


sub handle { $_[0]->{handle} }

sub new {
    my ($class, %arg) = @_;

    my $host      = $arg{host}      || '127.0.0.1';
    my $port      = $arg{port}      || 7496;
    my $client_id = $arg{client_id} || 0;

    my $self = bless {}, $class;

    # wait for connect
    my $cv = AnyEvent->condvar;

    $self->{handle} = AnyEvent::Handle->new(
        connect    => [$host, $port],
        on_error   => sub {
            die 'on_error';
            $self->handle->destroy;
        },
        on_failure => sub {
            die 'on_failure';
            $self->handle->destroy;
        },
        on_read    => sub {
            $self->process_message;
        },
    );
    $self->_write(59);
    $self->_read(sub { $self->{server_version} = shift; });
    $self->_read(sub { $self->{server_time}    = shift; $cv->send; });
    $self->_write($client_id);

    $cv->recv;

    return $self;
}

sub call {
    my ($self, $request) = @_;

    my @lines = $request->_serialize;

    $self->_write($_) foreach (@lines);
}

sub process_message {
    my ($self) = @_;

    $self->_read(sub { $self->_process_message(shift) });
}

sub _process_message {
    my ($self, $msg_id) = @_;

    my $class = Protocol::TWS->response_by_id($msg_id);
    unless ($class) {
        say "Unknown MSG ID '$msg_id'";
        return;
    }

    $self->_read_lines($class, [], $class->_lines);
}

sub _read_lines {
    my ($self, $class, $lines, $count) = @_;

    my $cv = AnyEvent->condvar;

    foreach (1 .. $count) {
        $cv->begin;
        $self->handle->unshift_read(
            line => "\0",
            sub { say "RECV: '$_[1]'"; push @$lines, $_[1]; $cv->end; },
        );
    }

    $cv->cb(sub { $self->_parse_message($class, $lines) });
}

sub _parse_message {
    my ($self, $class, $lines) = @_;

    my $response;
    eval {
        $response = $class->_parse(@$lines);
    };
    if ($@) {
        if (ref $@ and ref $@ eq 'SCALAR') {
            # read more lines
            $self->_read_lines($class, $lines, ${$@});
        } else {
            say "ERROR: $@";
            return;
        }
    }

    say Dumper $response;
}

sub _write {
    my ($self, $line) = @_;

    say "SEND: '$line'";

    $self->handle->push_write($line . "\0");
}

sub _read {
    my ($self, $cb) = @_;

    $self->handle->push_read(line => "\0", sub {
        my $line = $_[1];
        say "RECV: '$line'";
        $cb->($line);
    });
}

1;

