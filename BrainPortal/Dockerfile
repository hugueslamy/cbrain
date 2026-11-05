# syntax=docker/dockerfile:1
#
# CBRAIN BrainPortal - development image
#
# The Gemfile.lock is copied when it exists, so the image installs exactly
# the versions the bind-mounted app will ask for. Without it, the bundle
# is resolved at build time (and the lock is generated in the image).

ARG RUBY_VERSION=4.0.9
FROM ruby:${RUBY_VERSION}

# System packages needed to compile/run the gems in the Gemfile:
#   build-essential, pkg-config : native extensions (sassc, bcrypt_pbkdf, ed25519, x25519...)
#   git                         : gems fetched from git (zenodo_client, cbrain_client)
#   libmariadb-dev              : mysql2
#   mariadb-client              : rails dbconsole, db:prepare checks
#   libsodium-dev               : rbnacl
#   libvips                     : image_processing
#   libyaml-dev                 : psych
#   nodejs                      : ExecJS runtime for uglifier / coffee-rails
#   openssh-client              : SSH master connections and tunnels to the Bourreaux
#   rsync                       : Data Provider synchronization
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
      build-essential \
      pkg-config \
      git \
      libmariadb-dev \
      mariadb-client \
      libsodium-dev \
      libvips \
      libyaml-dev \
      nodejs \
      openssh-client \
      rsync && \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/archives

# Same UID/GID as the host user, so files written in the bind-mounted
# repository are not owned by root. The CBRAIN SSH identity is
# expected in /home/cbrain/.ssh (mounted by docker-compose), and the
# Data Provider cache in /home/cbrain/data/cache (a volume).
ARG CBRAIN_UID=1000
ARG CBRAIN_GID=1000
RUN groupadd --gid ${CBRAIN_GID} cbrain && \
    useradd --uid ${CBRAIN_UID} --gid ${CBRAIN_GID} --create-home --shell /bin/bash cbrain && \
    mkdir -p /home/cbrain/.ssh /home/cbrain/data/cache && \
    chmod 700 /home/cbrain/.ssh /home/cbrain/data/cache && \
    chown -R cbrain:cbrain /home/cbrain

WORKDIR /cbrain/BrainPortal

# Gems go in GEM_HOME (/usr/local/bundle, set by the ruby image), with their
# executables (puma, rails...) in /usr/local/bundle/bin, already in PATH.
# Do not set BUNDLE_PATH: Bundler would nest them under ruby/<version>/.
ENV RAILS_ENV="development" \
    BUNDLE_JOBS="4"

# Install gems; the lock is optional (the glob matches nothing if absent).
# The bundle belongs to 'cbrain' so Bundler can update it at runtime.
# The resolved lock is kept outside the app directory, which the checkout
# hides when bind-mounted: the entrypoint gives it to a checkout that has
# none, so the containers use the gems installed here (see bin/docker-entrypoint).
COPY Gemfile Gemfile.lock* .ruby-version ./
RUN gem update --system --no-document && \
    gem install bundler --no-document && \
    bundle install && \
    install -D -m 644 Gemfile.lock /usr/local/share/cbrain/Gemfile.lock && \
    chown -R cbrain:cbrain /usr/local/bundle

# Application code (in development it is also bind-mounted by docker-compose)
COPY --chown=cbrain:cbrain . .

USER cbrain

ENTRYPOINT ["/cbrain/BrainPortal/bin/docker-entrypoint"]

EXPOSE 3000
CMD ["./bin/rails", "server", "-b", "0.0.0.0", "-p", "3000"]
