package AnyEvent::TWS;

use strict;
use warnings;

use AnyEvent;
use AnyEvent::Handle;
use Data::Dumper;
use Protocol::TWS;


my %IGNORE_ERROR = map { $_ => 1 } qw/2104 2106/;


sub handle  { $_[0]->{handle} }
sub watcher { $_[0]->{watcher} }

sub new {
    my ($class, %arg) = @_;

    my $self = bless {
        host      => $arg{host}      || '127.0.0.1',
        port      => $arg{port}      || 7496,
        client_id => $arg{client_id} || 0,
    }, $class;

    return $self;
}

sub connect {
    my ($self) = @_;

    my $cv = AE::cv;
    $self->_init_watcher($cv);

    $self->{handle} = AnyEvent::Handle->new(
        connect  => [$self->{host}, $self->{port}],
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
    $self->_read(sub { $self->{server_version} = shift });
    $self->_read(sub { $self->{server_time}    = shift });
    $self->_write($self->{client_id});

    return $cv;
}

sub next_valid_id {
    (shift)->{next_valid_id}++;
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
        AE::log error => "Unknown MSG ID '$msg_id'";
        return;
    }

    $self->_read(sub { $self->_read_lines($class, shift, [], $class->_lines) });
}

sub _read_lines {
    my ($self, $class, $version, $lines, $count) = @_;

    my $cv = AE::cv;

    foreach (1 .. $count) {
        $cv->begin;
        $self->handle->unshift_read(
            line => "\0",
            sub {
                AE::log debug => "RECV: '$_[1]'";
                push @$lines, $_[1];
                $cv->end;
            },
        );
    }

    $cv->cb(sub { $self->_parse_message($class, $version, $lines) });
}

sub _parse_message {
    my ($self, $class, $version, $lines) = @_;

    # check minimum version
    if ($version < $class->_minimum_version) {
        AE::log error => "%s: got version %d, expected minimum %d",
            $class, $version, $class->_minimum_version;
        return;
    }

    my $response;
    eval {
        $response = $class->_parse($version, $lines);
    };
    if ($@) {
        if (ref $@ and ref $@ eq 'SCALAR') {
            # read more lines
            $self->_read_lines($class, $version, $lines, ${$@});
            return;
        } else {
            AE::log error => "ERROR: $@";
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
        AE::log warn => "No watcher for $name";
        AE::log warn => Dumper($response);
    }
}

sub _write {
    my ($self, $line) = @_;

    AE::log debug => "SEND: '$line'";

    $self->handle->push_write($line . "\0");
}

sub _read {
    my ($self, $cb) = @_;

    $self->handle->push_read(
        line => "\0",
        sub {
            my $line = $_[1];
            AE::log debug => "RECV: '$line'";
            $cb->($line);
        },
    );
}

sub _init_watcher {
    my ($self, $cv) = @_;

    $self->{watcher} = {};

    $cv->begin;
    $cv->begin;

    $self->_add_watcher(error           => _SYS_ => cont   => sub { $self->_handle_error(shift) });
    $self->_add_watcher(nextValidId     => _SYS_ => single => sub { $self->_handle_next_valid_id(shift);    $cv->end });
    $self->_add_watcher(managedAccounts => _SYS_ => single => sub { $self->_handle_managed_accounts(shift); $cv->end });
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

    # ignore market data messages
    return if $IGNORE_ERROR{$error->errorCode};

    warn Dumper $error;
}

sub _handle_next_valid_id {
    my ($self, $next_valid_id) = @_;

    $self->{next_valid_id} = $next_valid_id->id;
}

sub _handle_managed_accounts {
    my ($self, $managed_accounts) = @_;

    my @accounts = split /,/, $managed_accounts->accountsList;

    $self->{accounts} = \@accounts;
}

1;

__END__

=pod

=head1 NAME

AnyEvent::TWS - inofficial InteractiveBrokers Trader Workstation (TWS) API

=head1 SYNOPSIS

###TODO###

=head1 DESCRIPTION

This is an inofficial Perl port of InteractiveBrokers Trader Workstation API.
It is based of the C++ API (L<http://www.interactivebrokers.com/php/apiUsersGuide/apiguide.htm#apiguide/c/c.htm>).

Because it is based on L<AnyEvent> it can also be used in graphical programs.
In the examples directory is a simple L<Tk> program (and others).

In general it works like this: You create a request with a L<Protocol::TWS::Request>
subclass and hand it over to L<call>, togehter with a callback. Whenever a
response to your request comes in (which can be repeatedly), your callback is
called, together with a L<Protocol::TWS::Response> subclass as first parameter.
If you want to stop receiving repeated responses, there is usually a API
request to do that (starting with "cancel...").

=head1 CONSTRUCTOR

=head2 new

Accepts the following parameters:

=over

=item host - default: 127.0.0.1

=item port - default: 7496

=item client_id - default: 0

=back

It does not establish a connection, you have to call L<connect> for that.

=head1 METHODS

=head2 connect

Initiates a connection to InteractiveBrokers API. It returns a
L<condition variable|AnyEvent\CONDITION_VARIABLES>. You can call C<recv>
on it to block till the connection is established.

=head2 next_valid_id

Returns the next unused request ID.

It is important to always use a new request ID as this module uses the
request ID to match incoming messages to outstanding callbacks. So never
reuse a request ID.

=head2 call

Sends off a request. The first parameter is a L<Protocol::TWS::Request>
subclass, the second a callback. The callback is called everytime a
response to your original request comes in. This can be repeatedly.
But there are also a lot of requests, that just send exactly one response.

The first parameter to your callback is a L<Protocol::TWS::Response>
subclass. Use closures (or the request ID) to attach/match objects or
other parameters.

=head1 INTERNAL METHODS

=head2 process_message

Called internally whenever a new message on the socket arrives.

=head1 DEBUGGING

Set the C<AE_VERBOSE> environment variable to 5 (warn) or 8 (debug) to
get debugging output.

Be careful to always use a new request ID (see L<next_valid_id>), otherwise
the module might get confused.

If you are missing some responses, it could also be a bug. I have not tested
every type of request. If you find a bug, please email me a code example
together with a description what you expect as result.

If you have any questions or suggestions feel free to email me as well. There
are a lot of abstractions missing.

Also, if you have any examples that I can include, I would appreciate it.

=head1 SEE ALSO

L<http://www.interactivebrokers.com/en/p.php?f=programInterface>,
L<http://www.interactivebrokers.com/php/apiUsersGuide/apiguide.htm#apiguide/c/c.htm>,
L<Protocol::TWS>, L<Finance::TWS::Simple>

=head1 AUTHOR

Uwe Voelker uwe@uwevoelker.de

=cut
