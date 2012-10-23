#-------------------------------------------------------------------------------
# Argon::Worker implements a worker process that processes the payload of a
# Message and returns the results.
#-------------------------------------------------------------------------------
package Argon::Worker;

use Moose;
use Carp;
use namespace::autoclean;
use Argon qw/:commands/;

extends 'Argon::MessageProcessor';
with    'Argon::MessageServer';
with    'Argon::QueueManager';

sub process_message {
    my ($self, $message) = @_;
    my $response = $message->reply(CMD_ERROR);
    $response->set_payload("Not implemented");
    $self->msg_compelete($response);
}

__PACKAGE__->meta->make_immutable;

1;