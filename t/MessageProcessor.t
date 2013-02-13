use strict;
use warnings;

use Argon::Message;
use Argon::MessageProcessor;
use Argon        qw/:commands :statuses/;
use Test::More   qw/no_plan/;

my $proc = Argon::MessageProcessor->new();
my $msg  = Argon::Message->new(command => CMD_ACK);

# msg_accept
ok($proc->msg_accept($msg), 'msg_accept');
ok($proc->status->{$msg->id} == STATUS_QUEUED, 'msg_accept');
ok($proc->message->{$msg->id}->id eq $msg->id, 'msg_accept');

# msg_assigned
ok($proc->msg_assigned($msg), 'msg_assigned');
ok($proc->status->{$msg->id} == STATUS_ASSIGNED, 'msg_assigned');
ok($proc->message->{$msg->id}->id eq $msg->id, 'msg_assigned');

# msg_complete
ok($proc->msg_complete($msg), 'msg_complete');
ok($proc->status->{$msg->id} == STATUS_COMPLETE, 'msg_complete');
ok($proc->message->{$msg->id}->id eq $msg->id, 'msg_complete');

# msg_clear
my $result = $proc->msg_clear($msg);
ok($result->isa('Argon::Message'), 'msg_clear');
ok($result->id eq $msg->id, 'msg_clear');
ok(!exists $proc->message->{$msg->id}, 'msg_clear');
ok(!exists $proc->status->{$msg->id}, 'msg_clear');