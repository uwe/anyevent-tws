package AnyEvent::TWS;

use strict;
use warnings;
use feature qw/say/;

use AnyEvent;
use AnyEvent::Handle;
use Data::Dumper;

use lib '/home/uwe/repos/protocol-tws/lib';
use Protocol::TWS;


sub handle  { $_[0]->{handle} }
sub watcher { $_[0]->{watcher} }

sub new {
    my ($class, %arg) = @_;

    my $host      = $arg{host}      || '127.0.0.1';
    my $port      = $arg{port}      || 7496;
    my $client_id = $arg{client_id} || 0;

    my $self = bless {}, $class;

    $self->_init_watcher;

    # wait for connect
    my $cv = AnyEvent->condvar;

    $self->{handle} = AnyEvent::Handle->new(
        connect  => [$host, $port],
        on_error => sub {
            my ($handle, $fatal, $message) = @_;
            AE::log error => $message;
            if ($fatal) {
                AE::log error => 'fatal';
            }
        },
        on_read  => sub { $self->process_message },
    );
    $self->_write(59);
    $self->_read(sub { $self->{server_version} = shift; });
    $self->_read(sub { $self->{server_time}    = shift; $cv->send; });
    $self->_write($client_id);

    $cv->recv;

    return $self;
}

sub call {
    my ($self, $request, $cb) = @_;

    die 'CALLBACK missing' unless $cb;

    # register watcher
    my %response = $request->_response;
    my @watcher = ();
    while (my ($name, $type) = each %response) {
        my $id = '_ALL_';
        $id = $request->id if $request->can('id');
        push @watcher, [$name, $id];
        $self->_add_watcher($name, $id, $type, $cb, \@watcher);
    }

    $self->_write($_) foreach ($request->_serialize);
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

    $self->_read(sub { $self->_read_lines($class, shift, [], $class->_lines) });
}

sub _read_lines {
    my ($self, $class, $version, $lines, $count) = @_;

    my $cv = AnyEvent->condvar;

    foreach (1 .. $count) {
        $cv->begin;
        $self->handle->unshift_read(
            line => "\0",
            sub { say "RECV: '$_[1]'"; push @$lines, $_[1]; $cv->end; },
        );
    }

    $cv->cb(sub { $self->_parse_message($class, $version, $lines) });
}

sub _parse_message {
    my ($self, $class, $version, $lines) = @_;

    # check minimum version
    if ($version < $class->_minimum_version) {
        say sprintf(
            "%s: got version %d, expected minimum %d",
            $class, $version, $class->_minimum_version,
        );
        return;
    }

    my $response;
    eval {
        $response = $class->_parse($version, $lines);
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

    my $name   = $response->_name;
    my $called = 0;

    # check for system watchers
    if ($self->_handle_watcher($name, '_SYS_', $response)) {
        $called = 1;
    }

    # check for general watchers
    if ($self->_handle_watcher($name, '_ALL_', $response)) {
        $called = 1;
    }

    # check for specific watchers
    if ($response->can('id') and $self->_handle_watcher($name, $response->id, $response)) {
        $called = 1;
    }
    
    unless ($called) {
        say "No watcher for $name";
        say Dumper $response;
    }
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

sub _init_watcher {
    my ($self) = @_;

    $self->{watcher} = {};

    $self->_add_watcher(error           => _SYS_ => cont   => sub { $self->_handle_error(shift) });
    $self->_add_watcher(nextValidId     => _SYS_ => single => sub { $self->_handle_next_valid_id(shift) });
    $self->_add_watcher(managedAccounts => _SYS_ => single => sub { $self->_handle_managed_accounts(shift) });
}

sub _add_watcher {
    my ($self, $name, $id, $type, $cb, @param) = @_;

    if ($self->{watcher}->{$name}->{$id}) {
        die "Watcher already present for this id: name = $name, id = $id";
    }

    $self->{watcher}->{$name}->{$id} = [$type, $cb, @param];
}

sub _handle_watcher {
    my ($self, $name, $id, @args) = @_;

    my $watcher = $self->{watcher}->{$name}->{$id};
    return unless $watcher;

    my ($type, $cb, @param) = @$watcher;
    $cb->(@args);
    if ($type eq 'single') {
        $self->_remove_watcher($name, $id);
    }
    elsif ($type eq 'end') {
        foreach my $watcher (@{$param[0]}) {
            $self->_remove_watcher(@$watcher);
        }
    }

    return 1;
}

sub _remove_watcher {
    my ($self, $name, $id) = @_;

    delete $self->{watcher}->{$name}->{$id};
}

sub _handle_error {
    my ($self, $error) = @_;

    say Dumper $error;
}

sub _handle_next_valid_id {
    my ($self, $next_valid_id) = @_;

    $self->{next_valid_id} = $next_valid_id->id;
}

sub _handle_managed_accounts {
    my ($self, $managed_accounts) = @_;

    $self->{accounts} = split /,/, $managed_accounts->accountsList;
}


1;

