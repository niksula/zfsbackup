#!/bin/sh

# zfs filesystems/snapshots allow space in their name but not tab or newline
OLD_IFS=$IFS
IFS=$(printf '\n\t')

PATH=$PATH:/usr/sbin

usage() {
    echo "\
usage: $0 dataset target [target_host]

'dataset' will be backed up recursively under dataset 'target/POOLNAME' [on
target_host using ssh] where POOLNAME is derived from 'dataset'. Child datasets
that set fi.hut.niksula:backup_exclude to the value 'on' will not be included.

The running user should have ssh configuration set up properly and must have
permission to use the following zfs commands:
 - hold,receive,release on the target host
 - hold,release,send on the local host
without sudo/pfexec (use zfs allow)."
}

dataset="$1"
target="$2"
targetmachine="$3"

[ -z "$dataset" -o -z "$target" ] && { usage; exit 1; }

release() {
    if [ -n "$last" ]; then
        zfs release zfs-offsite $last
    fi
}

trap release INT TERM QUIT HUP 0

on_target() {
    if [ -z "$targetmachine" ]; then
        "$@"
    else
        ssh "$targetmachine" "$@"
    fi
}

pool=${dataset%%/*}
[ -z "$pool" ] && { echo fatal: unable to determine pool name from $dataset; exit 1; }

local_list=$(zfs list -Ho name,fi.hut.niksula:backup_exclude,type -S creation -t all -r $dataset) || { echo "fatal: could not get local dataset list" >&2; exit 1; }
remote_snaplist=$(on_target zfs list -Ho name -S creation -t snapshot -r ${target}/${pool}) || { echo "fatal: could not get remote dataset list" >&2; exit 1; }

# Extract non-snapshots and excluded datasets from local_list.
backup_datasets=$(echo "$local_list" | awk -F'	' '$2 != "on" && $3 != "snapshot" { print $1 }')

for fs in $backup_datasets; do
    unset last
    # list is sorted by creation date, return the first matching snap
    echo "$local_list" | while read -r ds excl type; do
        case "$ds" in
            "$fs"@*)
                # if snapshot is excluded skip it
                [ "$excl" = "on" ] && continue
                last="$ds"
                lastsnap=${last#*@}
                break
                ;;
        esac
    done
    # no snapshots apparently
    [ -n "$last" ] || { echo "W: skipping $fs: no unexcluded snapshots" ; continue; }
    zfs hold zfs-offsite $last
    # what's the incremental source, ie. latest snapshot the receiving side
    # has?
    from=$(echo "$remote_snaplist" | fgrep "${fs}@" | head -1)
    if [ -n "$from" ]; then
        fromsnap=${from#*@}
        [ "$lastsnap" = "$fromsnap" ] && { echo "W: $fs up to date at $fromsnap" >&2; continue; }
        zfs send -i "$fromsnap" "$last" | on_target zfs recv -Fd "${target}/${pool}" || { 
            echo "E: incremental recv '${last}' failed, keeping hold'" >&2
            continue
        }
    else
        echo "W: remote has no snapshots for $fs, starting over from $last"
        zfs send "$last" | on_target zfs recv -d "${target}/${pool}" || {
            echo "E: full recv '${last}' failed, keeping hold" >&2
            continue
        }

    fi
    # Backup success, create new holds and release possible old ones. We
    # already have a hold on the local side, need to create one on the remote
    # side
    on_target "zfs hold zfs-offsite '${target}/${last}' && [ -n '$from' ] && zfs release zfs-offsite '${target}/${fs}@${fromsnap}'"
    if [ -n "$from" ]; then
        zfs release zfs-offsite "${fs}@${fromsnap}" || echo "local release of ${fs}@${fromsnap} failed" >&2
    fi
done

trap '' INT QUIT TERM HUP 0
