package Argon::Manager;

use Moo;
use MooX::HandlesVia;
use Types::Standard qw(-types);
use Coro;
use Coro::Semaphore;
use Guard qw(scope_guard);
use Argon::Client;
use Argon::Tracker;
use Argon qw(K :logging :commands);

extends 'Argon::Dispatcher';

has workers => (
    is          => 'ro',
    isa         => Map[Str,InstanceOf['Argon::Client']],
    init_arg    => undef,
    default     => sub {{}},
    handles_via => 'Hash',
    handles     => {
        set_worker  => 'set',
        get_worker  => 'get',
        del_worker  => 'delete',
        has_worker  => 'exists',
        all_workers => 'keys',
    }
);

has tracking => (
    is          => 'ro',
    isa         => Map[Str,InstanceOf['Argon::Tracker']],
    init_arg    => undef,
    default     => sub {{}},
    handles_via => 'Hash',
    handles     => {
        set_tracking => 'set',
        get_tracking => 'get',
        del_tracking => 'delete',
    }
);

has sem_capacity => (
    is       => 'ro',
    isa      => InstanceOf['Coro::Semaphore'],
    init_arg => undef,
    default  => sub { Coro::Semaphore->new(0) },
    handles  => {
        current_capacity => 'count',
    }
);

has capacity => (
    is       => 'ro',
    isa      => Int,
    init_arg => undef,
    default  => 0,
);

sub inc_capacity {
    my ($self, $amount) = @_;
    $amount //= 1;
    $self->{capacity} += $amount;
}

sub dec_capacity {
    my ($self, $amount) = @_;
    $amount //= 1;
    $self->{capacity} -= $amount;
}

sub init {
    my $self = shift;
    $self->respond_to($CMD_REGISTER, K('cmd_register', $self));
    $self->respond_to($CMD_QUEUE,    K('cmd_queue',    $self));
}

sub deregister {
    my ($self, $worker) = @_;
    if ($self->has_worker($worker)) {
        my $lost_capacity = $self->get_tracking($worker)->workers;
        $self->dec_capacity($lost_capacity);
        $self->sem_capacity->adjust(-$lost_capacity);
        $self->del_worker($worker);
        $self->del_tracking($worker);
        WARN 'Lost connection to worker "%s"', $worker;
        DEBUG 'Capacity at %d', $self->capacity;
    }
}

sub start_monitor {
    my ($self, $worker) = @_;
    my $client = $self->get_worker($worker);

    async_pool {
        scope_guard { $self->deregister($worker) };

        while (1) {
            my $msg = Argon::Message->new(cmd => $CMD_PING);
            my $reply = $client->send($msg) or last;

            if ($reply->cmd == $CMD_ACK) {
                Coro::AnyEvent::sleep $Argon::POLL_INTERVAL;
            } else {
                WARN 'Worker monitor detected a problem: %s', $reply->payload;
                $self->deregister($worker);
            }
        }
    };
}

sub cmd_register {
    my ($self, $msg) = @_;
    my $key      = $msg->key;
    my $host     = $msg->payload->{host};
    my $port     = $msg->payload->{port};
    my $capacity = $msg->payload->{capacity};

    # Create client
    my $client = Argon::Client->new(host => $host, port => $port);

    INFO 'Connecting to worker "%s"', $key;
    $client->connect;
    INFO 'Connected to worker "%s"', $key;

    # Create tracker
    my $tracker = Argon::Tracker->new(
        tracking => $Argon::TRACK_MESSAGES,
        workers  => $capacity,
    );

    # Store worker and worker tracking
    $self->set_worker($key, $client);
    $self->set_tracking($key, $tracker);

    # Increment capacity and release up to $capacity slots
    $self->inc_capacity($capacity);
    $self->sem_capacity->adjust($capacity);

    # Start monitor
    $self->start_monitor($key);

    DEBUG 'Capacity at %d', $self->capacity;

    return $msg->reply(
        cmd     => $CMD_ACK,
        payload => { client_addr => $client->addr },
    );
}

sub cmd_queue {
    my ($self, $msg, $addr) = @_;

    # Return an error if there are no workers registered
    return $msg->reply(cmd => $CMD_ERROR, payload => 'No workers registered.')
        if $self->capacity == 0;

    # Acquire capacity slot
    $self->sem_capacity->down;

    # Release capacity slot once complete
    scope_guard { $self->sem_capacity->up };

    # Get the next available worker
    my $cmp = sub { $self->get_tracking($_[0])->est_proc_time };
    my @workers =
        sort { $cmp->($a) <=> $cmp->($b) }
        grep { $self->get_tracking($_)->capacity > 0 }
        $self->all_workers;

    my $worker = $workers[0];

    # Execute with tracking
    $self->get_tracking($worker)->start_request($msg->id);

    scope_guard {
        # If the worker connection was lost while the request was
        # outstanding, the tracker may be missing, so completing
        # the request must account for this appropriately.
        $self->get_tracking($worker)->end_request($msg->id)
            if $self->has_worker($worker);
    };

    # Assign the task
    $msg->{key} = $worker;

    # TODO this is hanging sometimes and causing delays in responses
    my $reply = eval { $self->get_worker($worker)->send($msg) };

    if ($@) {
        WARN 'Worker error (%s) - disconnecting: %s', $worker, $@;
        $self->deregister($worker);
        return $msg->reply(cmd => $CMD_ERROR, payload => "An error occurred routing the request: $@");
    } else {
        return $reply;
    }
}

1;
