package Argon::Role::MessageServer;

use Moose::Role;
use Carp;
use namespace::autoclean;
use Argon qw/:commands :statuses LOG EOL CHUNK_SIZE/;
use Argon::MessageProcessor;

requires 'msg_accept';
requires 'status';
requires 'respond_to';
requires 'send_reply';

has 'endline' => (
    is      => 'ro',
    isa     => 'Str',
    default => EOL,
);

has 'chunk_size' => (
    is      => 'ro',
    isa     => 'Int',
    default => CHUNK_SIZE,
);

#-------------------------------------------------------------------------------
# Configures the server, mapping commands to local methods.
#-------------------------------------------------------------------------------
sub BUILD {}
after 'BUILD' => sub {
    my $self = shift;
    $self->respond_to(CMD_QUEUE,  sub { $self->reply_queue(@_)  });
};

#-------------------------------------------------------------------------------
# Replies to request to accept/queue a new message.
#-------------------------------------------------------------------------------
sub reply_queue {
    my ($self, $msg) = @_;
    eval { $self->msg_accept($msg) };
    if ($@) {
        my $error = $@;
        my $reply = $msg->reply(CMD_REJECTED);
        $reply->set_payload($error);
        return $reply;
    } else {
        return;
    }
}

around 'msg_complete' => sub {
    my ($orig, $self, $msg) = @_;
    $self->$orig($msg);
    $self->send_reply($msg);
    $self->msg_clear($msg);
};

no Moose;

1;
