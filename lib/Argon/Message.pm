package Argon::Message;

use strict;
use warnings;
use Carp;

use Moose;
use MooseX::StrictConstructor;
use Moose::Util::TypeConstraints;
use namespace::autoclean;

use Time::HiRes  qw/time/;
use Data::UUID   qw//;
use MIME::Base64 qw//;
use Storable     qw//;;
use Argon        qw/:priorities/;

enum 'Argon::Message::Priority', [PRI_MAX .. PRI_MIN];

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

# Message priority, used when queueing messages at entry point
has 'priority' => (
    is      => 'ro',
    isa     => 'Argon::Message::Priority',
    default => PRI_NORMAL,
);

# Processing instruction
has 'command' => (
    is       => 'ro',
    isa      => 'Int',
    required => 1,
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
    return join($Argon::MESSAGE_SEPARATOR, $self->command, $self->priority, $self->id, $self->timestamp, $payload);
}

sub decode {
    my ($cmd, $pri, $id, $timestamp, $payload) = split $Argon::MESSAGE_SEPARATOR, $_[0];
    my $msg = Argon::Message->new(command => $cmd, priority => $pri, id => $id, timestamp => $timestamp);
    $msg->encoded($payload) if $payload ne '-';
    return $msg;
}

#-------------------------------------------------------------------------------
# Creates a new Message object with the command verb as a reply. The payload is
# not included in the reply.
#-------------------------------------------------------------------------------
sub reply {
    my ($self, $cmd) = @_;
    my $msg = Argon::Message->new(command => $cmd, id => $self->id, priority => $self->priority);
    return $msg;
}

no Moose;
no Moose::Util::TypeConstraints;
__PACKAGE__->meta->make_immutable;

1;