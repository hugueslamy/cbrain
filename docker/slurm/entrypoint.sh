#!/bin/bash -e

# Entrypoint of the emulated Slurm cluster. Runs as root.
#   slurm-entrypoint slurmdbd | slurmctld | slurmd
# The configuration is bind-mounted from docker/slurm/etc at /etc/slurm,
# except for slurmdbd (see below).

role="$1"

# Munge: one key for the whole cluster, Bourreau included, in the
# munge_key volume. The first container to boot creates it (mv -n: no overwrite).
shared_key=/etc/munge-shared/munge.key
if [ ! -s "$shared_key" ]; then
  dd if=/dev/urandom bs=1 count=1024 status=none > "$shared_key.$$"
  mv -n "$shared_key.$$" "$shared_key"
  rm -f "$shared_key.$$"
fi
install -o munge -g munge -m 400 "$shared_key" /etc/munge/munge.key
install -d -o munge -g munge -m 755 /run/munge
runuser -u munge -- /usr/sbin/munged

case "$role" in
  slurmdbd)
    # slurmdbd always reads /etc/slurm/slurmdbd.conf and refuses it if others
    # can read it (it holds the DB password). A bind mount keeps the host's
    # owner and mode, so the sources are mounted at /etc/slurm-src and copied.
    install -o slurm -g slurm -m 600 /etc/slurm-src/slurmdbd.conf.in /etc/slurm/slurmdbd.conf
    exec /usr/sbin/slurmdbd -D
    ;;
  slurmctld)
    install -d -o slurm -g slurm -m 755 /var/spool/slurmctld
    # The controller registers the cluster in slurmdbd; wait for it, or
    # accounting (sacct) stays empty until the next restart
    for i in $(seq 1 30); do
      timeout 1 bash -c '</dev/tcp/slurmdbd/6819' 2>/dev/null && break
      echo "Waiting for slurmdbd..."
      sleep 2
    done
    exec /usr/sbin/slurmctld -D -i
    ;;
  slurmd)
    install -d -m 755 /var/spool/slurmd
    exec /usr/sbin/slurmd -D
    ;;
  *)
    exec "$@"
    ;;
esac
