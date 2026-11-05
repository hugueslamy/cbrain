# syntax=docker/dockerfile:1
#
# Emulated HPC for CBRAIN development: one image for every Slurm role.
# The entrypoint argument selects the role: slurmdbd, slurmctld or slurmd.
#
# Same Debian release as the Bourreau image (ruby:4.0.9 is trixie), so
# the Bourreau's slurm-client matches these daemons' version.

FROM debian:trixie-slim

# System packages:
#   slurmctld, slurmd, slurmdbd, slurm-client : Slurm daemons and commands
#   munge                                     : Slurm authentication
#   lmod                                      : 'module load', as on an HPC
#   ffmpeg                                    : example science tool, exposed
#                                               only through 'module load ffmpeg'
#   procps                                    : ps, used by runtime_info.sh
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
      slurmctld \
      slurmd \
      slurmdbd \
      slurm-client \
      munge \
      lmod \
      ffmpeg \
      procps && \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/archives

# Software tree, as on an HPC: tools live under /opt/apps and are not in
# the default PATH. Jobs get them with 'module load <tool>'.
# ffmpeg's libraries stay in /usr/lib; only the commands are moved.
RUN set -e; \
    version=$(dpkg-query -W -f='${Version}' ffmpeg | sed -e 's/^[0-9]*://' -e 's/[-+~].*//'); \
    mkdir -p /opt/apps/ffmpeg/$version/bin /opt/apps/modulefiles/ffmpeg; \
    for cmd in ffmpeg ffprobe ffplay; do \
      [ -e /usr/bin/$cmd ] && mv /usr/bin/$cmd /opt/apps/ffmpeg/$version/bin/; \
    done; \
    { echo "help([[ffmpeg $version (Debian package)]])"; \
      echo "whatis('Name: ffmpeg')"; \
      echo "whatis('Version: $version')"; \
      echo "prepend_path('PATH', '/opt/apps/ffmpeg/$version/bin')"; \
    } > /opt/apps/modulefiles/ffmpeg/$version.lua; \
    echo /opt/apps/modulefiles >> /etc/lmod/modulespath
# (modulespath: 'module' also works in login shells on the node, for
# debugging: docker compose exec -u cbrain c1 bash -l. Jobs get it from
# the Slurm TaskProlog, docker/slurm/etc/task_prolog.sh.)

# Apptainer, for tools configured with a container image. The jobs only run
# 'apptainer exec'; the Bourreau builds the images (task setup) into the
# Data Provider cache, which this node sees on the shared volume.
#
# apptainer-suid: unprivileged Apptainer needs user namespaces, which this
# setup cannot provide (Docker's seccomp and AppArmor block them, and Ubuntu
# hosts with kernel.apparmor_restrict_unprivileged_userns=1 block them even
# when unconfined). The setuid starter works, but only in a privileged
# container: see 'c1' in docker-compose.slurm.yml. Real HPCs often run Apptainer
# without setuid; that difference is a limit of this emulator.
# Release packages pinned by checksum (the release publishes none).
ARG APPTAINER_VERSION=1.5.5
ADD --checksum=sha256:82a6e5ead21d3e19de522a9e0bbeb59958323e316dc9d019a128b0cc8e99d863 \
    https://github.com/apptainer/apptainer/releases/download/v${APPTAINER_VERSION}/apptainer_${APPTAINER_VERSION}-trixie+_amd64.deb \
    /tmp/apptainer.deb
ADD --checksum=sha256:5b7bac9b2ff93f74e7423b9ba8afd2f99d044968e1f030e4776cdcf7af61a16b \
    https://github.com/apptainer/apptainer/releases/download/v${APPTAINER_VERSION}/apptainer-suid_${APPTAINER_VERSION}-trixie+_amd64.deb \
    /tmp/apptainer-suid.deb
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y /tmp/apptainer.deb /tmp/apptainer-suid.deb && \
    rm -rf /tmp/apptainer*.deb /var/lib/apt/lists/* /var/cache/apt/archives

# Same user and UID as on the Bourreau: jobs run as 'cbrain', and the
# work directories on the shared volume belong to it
ARG CBRAIN_UID=1000
ARG CBRAIN_GID=1000
RUN groupadd --gid ${CBRAIN_GID} cbrain && \
    useradd --uid ${CBRAIN_UID} --gid ${CBRAIN_GID} --create-home --shell /bin/bash cbrain

COPY entrypoint.sh /usr/local/bin/slurm-entrypoint
ENTRYPOINT ["/usr/local/bin/slurm-entrypoint"]
