#-------------------------------------------------------------------------------
# Nodes manage a pool of Worker processes. Like a Cluster, they route tasks to
# Workers (without worrying about each processes' speed, since they are local),
# and store the results.
#-------------------------------------------------------------------------------
package Argon::Node;

use Moose;
use Carp;
use namespace::autoclean;



__PACKAGE__->meta->make_immutable;

1;