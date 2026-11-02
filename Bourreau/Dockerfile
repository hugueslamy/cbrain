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
      procps && \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/archives

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
COPY Gemfile Gemfile.lock* ./
RUN gem update --system --no-document && \
    gem install bundler --no-document && \
    bundle install && \
    chown -R cbrain:cbrain /usr/local/bundle

COPY bin/docker-entrypoint /usr/local/bin/bourreau-entrypoint

EXPOSE 22
ENTRYPOINT ["/usr/local/bin/bourreau-entrypoint"]
CMD ["/usr/sbin/sshd", "-D", "-e"]
