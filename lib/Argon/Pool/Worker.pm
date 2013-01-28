package Argon::Pool::Worker;
use Moose;
use Carp;
use Argon qw/LOG :commands/;

extends 'AnyEvent::Worker';

has 'request_count' => (
	traits   => ['Counter'],
	is  	 => 'ro',
	isa 	 => 'Int',
	init_arg => undef,
	default  => 0,
	handles  => { inc => 'inc' }
);

#-------------------------------------------------------------------------------
# Configures AnyEvent::Worker to use Argon::Pool::Worker::process.
#-------------------------------------------------------------------------------
sub new {
    my $class = shift;
    return $class->SUPER::new(\&loop, @_);
}

#-------------------------------------------------------------------------------
# Processes an individual task.
#-------------------------------------------------------------------------------
sub loop {
    my $message = shift;

    my $result = eval {
        my ($class, $params) = @{$message->get_payload};
        require "$class.pm";
        
        croak 'Tasks must implement Argon::Role::Task'
            unless $class->does('Argon::Role::Task');
        
        my $instance = $class->new(@$params);
        $instance->run;
    };

    my $reply;
    if ($@) {
        my $error = $@;
        $reply = $message->reply(CMD_ERROR);
        $reply->set_payload($error);
    } else {
        $reply = $message->reply(CMD_COMPLETE);
        $reply->set_payload($result);
    }

    my $r = $reply->encode();
    return $r;
}

no Moose;
__PACKAGE__->meta->make_immutable(inline_constructor => 0);

1;