Argon
=====
Note: Argon is still under active development. Many features are not complete.

Argon is a platform for distributed services written in Modern Perl. Its goals
are:

    * Simple design of distributed systems
    * Task prioritization
    * Uniformity of worker nodes
    * Bounded queues
    * Robust design


Simple design of distributed systems
------------------------------------
Argon applications are built from simple components. The most basic piece is an
Argon::Node, which manages a configurable pool of local Perl processes. Acting
alone, a node can listen on a TCP/IP socket and accept new tasks.

Multiple nodes work in tandem through an Argon::Cluster. Clusters maintain a
pool of nodes, routing tasks to the most available node based on it's recent
performance and current load.

Tasks are assigned by passing a class name and arguments to an instance of an
Argon::Client. Because all components of the system use the same protocol, it
does not matter whether a client connects to a node or a cluster. Tasks are
sent to the specified entry point to the Argon application and routed
appropriately. The client's caller is suspended (using Coro) until the task is
successfully completed.


Task prioritization
---------------------
Tasks are prioritized and the most important tasks are pushed to the front of
the line. In cases of high load, the system will reject tasks which it cannot
handle. The client accounts for this transparently, rescheduling the task to be
handled after the system again becomes available.

Clusters actively track task delivery and route incoming tasks to the most
available node.


Uniformity of worker nodes
--------------------------
With many systems currently available, individual worker processes handle a
specific type of task. To increase a task's priority, more worker processes
are launched and configured to query a specific job queue.

Argon worker processes are controlled by a node as a pool. Any worker may
handle any type of task. This way, no worker processes remain idle, allowing
another, busier worker's queue to grow. This prevents backlogs and keeps the
system more responsive.


Bounded queues
--------------
Task queues are bounded. By enforcing a cap on the number of tasks that may be
queued, the application is protected from DOS-like attacks and remains
responsive at all times. This prevents queues from growing so large that a
spike in traffic causes a secondary delay in restoring responsiveness as the
backlog of tasks are first cleared.

Tasks that cannot be added due to queue constraints are rejected and the client
software is notified. Client software will automatically and transparently
retry tasks that have been rejected.


Robust design
-------------
Argon is designed to ensure that all parts of the system function independently
of the other parts. Nodes do not crash if their supervising cluster becomes
unavailable and vice versa; clusters will continue to route to any available nodes
until a disconnected node comes back online.

New nodes may be added to the system without restarting the cluster. This allows
an application administrator to seamlessly boost performance without
interrupting service for existing clients.

Usage
=====
See `/bin` for examples of usage. More to come as the design is solidified.

LICENSE AND COPYRIGHT
=====================

Copyright (C) 2013 "Jeff Ober"

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.