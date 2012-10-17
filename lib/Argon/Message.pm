package Argon::Message;

use Moose;
use Carp;
use MIME::Base64    qw//;
use Storable        qw//;
use Argon           qw/:priorities NO_ID MESSAGE_SEPARATOR/;

has 'command'    => (is => 'ro', isa => 'Int', required => 1);
has 'priority'   => (is => 'rw', isa => 'Int', default => PRI_NORMAL);
has 'id'         => (is => 'ro', isa => 'Int', default => NO_ID);
has 'decoded'    => (is => 'rw', init_arg => undef, clearer => 'clear_decoded', predicate => 'is_decoded');
has 'encoded'    => (is => 'rw', init_arg => undef, clearer => 'clear_encoded', predicate => 'is_encoded');

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
    $self->is_encoded || croak 'Missing payload';

    unless ($self->is_decoded) {
        my $image   = MIME::Base64::decode_base64($self->encoded);
        my $payload = Storable::thaw($image);
        $self->decoded(@$payload);
    }

    return $self->decoded;
}

sub encode {
    my $self = shift;
    $self->is_encoded || croak 'Missing payload';
    return join(MESSAGE_SEPARATOR, $self->command, $self->priority, $self->id, $self->encoded);
}

sub decode {
    my ($cmd, $pri, $id, $payload) = split MESSAGE_SEPARATOR, $_[0];
    my $msg = Argon::Message->new(command => $cmd, priority => $pri, id => $id);
    $msg->encoded($payload);
    return $msg;
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;
