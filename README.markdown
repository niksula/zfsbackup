Niksula zfs backup script
=========================

This program sends recursive backups of zfs datasets to other systems (which
must also run zfs). Property-based exclude is not supported. It runs on the
source host(s), and does not require a component running on the target host. If
you want a backup solution that runs from a central host, take a look at
[Zetaback](http://labs.omniti.com/labs/zetaback).

Tested on illumos (OmniOS), possibly modifiable to run on other systems as
well.

You are required to create snapshots of your filesystems via some other method
(eg. cron jobs). This script only sends existing snapshots to the target backup
host.

The program can, but should not, be run as root. Instead, create a user on the
source and target systems and delegate the necessary permissions with 'zfs
allow' (see the usage message for details).

zfs holds are used to ensure the backup source and target do not get
desynchronized (ie. both will always have the incremental source for the next
run). This makes it easy to prune old backup snapshots from the target host if
you don't want to keep them: just try to destroy them all, and the hold will
prevent the removal of the next incremental source.

A full backup run sends all available snapshots and is thus quite slow, but
consequent incrementals should be much faster since intermediate snapshots are
not sent. We are considering limiting the initial backup to a single snapshot
in the future (but this isn't trivial since illumos zfs cannot send a single
recursive snapshot as of this writing).

Recursive holds and send -R were chosen in favor of property-based exclude
because it is simpler to create a well-performing system this way, since send
-R cand multiple snapshots over one pipe. Sending each fs separately, as is
required for property-based exclude, would mean a pipe and thus an ssh
connection for each filesystem (or ssh multiplexing, which SunSSH does not
do), which is prohibitively slow at least for our use case of several thousands
of smallish home directory file systems.
