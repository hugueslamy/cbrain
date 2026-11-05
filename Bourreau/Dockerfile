# syntax=docker/dockerfile:1
#
# CBRAIN Bourreau - development image
#
# This image does not run Rails itself. It runs sshd; the BrainPortal
# connects as user 'cbrain' and starts the Bourreau with
# script/cbrain_remote_ctl, through an SSH master connection that also
# carries the reverse DB tunnel and the agent forwarding.
#
# As for the portal, the Gemfile.lock is copied when it exists;
# otherwise the bundle is resolved at build time.

ARG RUBY_VERSION=4.0.9
FROM ruby:${RUBY_VERSION}

# System packages:
#   build-essential, pkg-config : native extensions (bcrypt_pbkdf, ed25519, x25519...)
#   git                         : gems fetched from git, file revisions
#   libmariadb-dev              : mysql2
#   libsodium-dev               : rbnacl
#   libyaml-dev                 : psych
#   openssh-server              : the portal controls the Bourreau through SSH
#   rsync                       : Data Provider synchronization
#   netcat-openbsd, iproute2    : socket checks in script/cbrain_remote_ctl (nc, ss)
#   procps                      : ps, used to find workers
#   python3-venv                : virtual environment for Boutiques (bosh)
#   slurm-client, munge         : login node of the emulated Slurm cluster
#                                 (Slurm setup: sbatch, squeue, sacct...;
#                                 see docker/slurm)
# No science tools here: they come from Apptainer images (or, with Slurm,
# from modules on the compute nodes, as on an HPC).
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
      build-essential \
      pkg-config \
      git \
      libmariadb-dev \
      libsodium-dev \
      libyaml-dev \
      openssh-server \
      rsync \
      netcat-openbsd \
      iproute2 \
      procps \
      python3-venv \
      slurm-client \
      munge && \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/archives

# Boutiques: Bourreaux run 'bosh exec simulate' and 'bosh exec launch' for
# Boutiques tasks. /usr/local/bin is in the PATH of SSH sessions and job scripts.
ARG BOUTIQUES_VERSION=0.5.33
RUN python3 -m venv /opt/boutiques && \
    /opt/boutiques/bin/pip install --no-cache-dir "boutiques==${BOUTIQUES_VERSION}" && \
    ln -s /opt/boutiques/bin/bosh /usr/local/bin/bosh

# Apptainer, for tools whose ToolConfig has a container image. The Bourreau
# runs 'apptainer build' during task setup (docker:// -> SIF, cached in the
# Data Provider cache), which needs no privileges. The tasks' 'apptainer
# exec' runs here with the UNIX setup, on the compute node with Slurm.
#
# apptainer-suid: unprivileged 'apptainer exec' needs user namespaces, which
# Docker cannot provide (its seccomp and AppArmor profiles block them, and
# Ubuntu hosts with kernel.apparmor_restrict_unprivileged_userns=1 block
# them even when unconfined). The setuid starter works, but only in a
# privileged container: see 'bourreau' in docker-compose.unix.yml.
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

# Same UID/GID as the host user, so files written in the bind-mounted
# repository are not owned by root
ARG CBRAIN_UID=1000
ARG CBRAIN_GID=1000
RUN groupadd --gid ${CBRAIN_GID} cbrain && \
    useradd --uid ${CBRAIN_UID} --gid ${CBRAIN_GID} --create-home --shell /bin/bash cbrain && \
    mkdir -p /home/cbrain/.ssh /home/cbrain/data && \
    chmod 700 /home/cbrain/.ssh

# SSH sessions don't inherit the Docker environment (PATH, GEM_HOME...).
# Load it first thing in .bashrc, before Debian's early return for
# non-interactive shells. script/cbrain_bashrc sources ~/.bashrc.
RUN { echo '[ -f "$HOME/.cbrain_docker_env" ] && . "$HOME/.cbrain_docker_env"'; \
      cat /home/cbrain/.bashrc; } > /tmp/bashrc && \
    mv /tmp/bashrc /home/cbrain/.bashrc && \
    chown -R cbrain:cbrain /home/cbrain

# sshd: key-only login for 'cbrain'. StreamLocalBindUnlink lets the portal
# recreate the reverse DB tunnel socket when a stale one is left behind.
# Host keys live in /etc/ssh/hostkeys (a volume, created by the entrypoint).
RUN mkdir -p /run/sshd && \
    { echo 'HostKey /etc/ssh/hostkeys/ssh_host_ed25519_key'; \
      echo 'HostKey /etc/ssh/hostkeys/ssh_host_ecdsa_key'; \
      echo 'HostKey /etc/ssh/hostkeys/ssh_host_rsa_key'; \
      echo 'PasswordAuthentication no'; \
      echo 'KbdInteractiveAuthentication no'; \
      echo 'PermitRootLogin no'; \
      echo 'AllowUsers cbrain'; \
      echo 'AllowTcpForwarding yes'; \
      echo 'AllowStreamLocalForwarding yes'; \
      echo 'AllowAgentForwarding yes'; \
      echo 'StreamLocalBindUnlink yes'; \
    } > /etc/ssh/sshd_config.d/cbrain.conf

WORKDIR /cbrain/Bourreau

# Gems go in GEM_HOME (/usr/local/bundle, set by the ruby image), with their
# executables (puma, rails...) in /usr/local/bundle/bin, already in PATH.
# Do not set BUNDLE_PATH: Bundler would nest them under ruby/<version>/.
ENV RAILS_ENV="development" \
    BUNDLE_JOBS="4"

# Install gems; the lock is optional (the glob matches nothing if absent).
# The bundle belongs to 'cbrain' so Bundler can update it from SSH sessions.
# The resolved lock is kept outside the app directory, which the checkout
# hides when bind-mounted: the entrypoint gives it to a checkout that has none.
COPY Gemfile Gemfile.lock* .ruby-version ./
RUN gem update --system --no-document && \
    gem install bundler --no-document && \
    bundle install && \
    install -D -m 644 Gemfile.lock /usr/local/share/cbrain/Gemfile.lock && \
    chown -R cbrain:cbrain /usr/local/bundle

COPY bin/docker-entrypoint /usr/local/bin/bourreau-entrypoint

EXPOSE 22
ENTRYPOINT ["/usr/local/bin/bourreau-entrypoint"]
CMD ["/usr/sbin/sshd", "-D", "-e"]
