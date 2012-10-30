use strict;
use warnings;
use Carp;
use EV;
use AnyEvent;

require Argon::Server;
require Argon::Node;

my $server = Argon::Server->new(
    port => 8888,
);

my $node = Argon::Node->new(
    server      => $server,
    concurrency => 2,
    queue_limit => 100,
);

$server->start;
$node->initialize;
EV::run;