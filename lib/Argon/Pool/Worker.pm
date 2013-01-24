package Argon::Pool::Worker;
use Moose;
use Carp;

extends 'AnyEvent::Worker';

has 'request_count' => (
	traits   => ['Counter'],
	is  	 => 'ro',
	isa 	 => 'Int',
	init_arg => undef,
	default  => 0,
	handles  => { inc => 'inc' }
);

no Moose;
__PACKAGE__->meta->make_immutable(inline_constructor => 0);

1;