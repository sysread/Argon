package Argon::Message;

use Moose;
use Carp;
use namespace::autoclean;
use Argon       qw/:priorities LOG MESSAGE_SEPARATOR/;
use Time::HiRes qw/time/;
use overload '<=>'  => \&compare;
use overload 'bool' => sub { defined $_[0] };

require Data::UUID;
require MIME::Base64;
require Storable;

# Time stamp, used to sort incoming messages
has 'timestamp' => (
    is       => 'rw',
    isa      => 'Num',
    default  => sub { time },
);

# Message id, assigned at system entry point (UUID)
has 'id' => (
    is      => 'ro',
    isa     => 'Str',
    lazy    => 1,
    default => sub { Data::UUID->new->create_str },
);

# Processing instruction
has 'command' => (
    is       => 'ro',
    isa      => 'Int',
    required => 1,
);

# Message priority (lower value is higher priority)
has 'priority' => (
    is      => 'rw',
    isa     => 'Int',
    default => PRI_NORMAL,
);

# Private - storage for encoded and decoded payloads
has 'decoded' => (
    is        => 'rw',
    init_arg  => undef,
    clearer   => 'clear_decoded',
    predicate => 'is_decoded',
);

has 'encoded' => (
    is        => 'rw',
    init_arg  => undef,
    clearer   => 'clear_encoded',
    predicate => 'is_encoded',
);


sub update_timestamp {
    my $self = shift;
    $self->timestamp(time);
}

sub payload {
    return @_ == 1 ? $_[0]->get_payload : $_[0]->set_payload($_[1]);
}

sub set_payload {
    my ($self, $data) = @_;
    my $image   = Storable::nfreeze([$data]);
    my $payload = MIME::Base64::encode_base64($image, '');

    $self->clear_decoded;
    $self->encoded($payload);
};

sub get_payload {
    my $self = shift;
    return unless $self->is_encoded;

    unless ($self->is_decoded) {
        my $image   = MIME::Base64::decode_base64($self->encoded);
        my $payload = Storable::thaw($image);
        $self->decoded(@$payload);
    }

    return $self->decoded;
}

sub encode {
    my $self = shift;
    my $payload = $self->encoded || '-';
    return join(MESSAGE_SEPARATOR, $self->command, $self->priority, $self->id, $self->timestamp, $payload);
}

sub decode {
    my ($cmd, $pri, $id, $timestamp, $payload) = split MESSAGE_SEPARATOR, $_[0];
    my $msg = Argon::Message->new(command => $cmd, priority => $pri, id => $id, timestamp => $timestamp);
    $msg->encoded($payload) if $payload ne '-';
    return $msg;
}

#-------------------------------------------------------------------------------
# Creates a new Message object with the command verb as a reply. If the second
# optional argument is true (false by default), includes the message payload in
# the reply.
#-------------------------------------------------------------------------------
sub reply {
    my ($self, $cmd, $include_payload) = @_;
    my $msg = Argon::Message->new(command => $cmd, id => $self->id, priority => $self->priority);
    $msg->encoded($self->encoded) if $include_payload;
    return $msg;
}

#-------------------------------------------------------------------------------
# Compares two Messages and returns and the equivalent of the <=> operator.
# Comparison is done based first on priority (lower priority is "higher" for
# sorting) and second based on its timestamp.
#-------------------------------------------------------------------------------
sub compare {
    my ($self, $other, $swap) = @_;
    my ($x, $y) = $swap ? ($other, $self) : ($self, $other);
    if ($x->priority != $y->priority) {
        return $y->priority <=> $x->priority;
    } else {
        return $y->timestamp <=> $x->timestamp;
    }
}

__PACKAGE__->meta->make_immutable;

1;
