# syntax=docker/dockerfile:1.18

ARG TARGETPLATFORM=${TARGETPLATFORM}
ARG BUILDPLATFORM=${BUILDPLATFORM}

FROM cgr.dev/chainguard/ruby:latest AS ruby-prod

ARG MASTODON_VERSION_PRERELEASE=""
ARG MASTODON_VERSION_METADATA=""
ARG SOURCE_COMMIT=""

ARG RAILS_SERVE_STATIC_FILES="true"
ARG RUBY_YJIT_ENABLE="1"
ARG TZ="Etc/UTC"

# Apply Mastodon build options based on options above
ENV \
  MASTODON_VERSION_PRERELEASE="${MASTODON_VERSION_PRERELEASE}" \
  MASTODON_VERSION_METADATA="${MASTODON_VERSION_METADATA}" \
  SOURCE_COMMIT="${SOURCE_COMMIT}" \
  RAILS_SERVE_STATIC_FILES=${RAILS_SERVE_STATIC_FILES} \
  RUBY_YJIT_ENABLE=${RUBY_YJIT_ENABLE} \
  TZ=${TZ}

ENV \
  BIND="0.0.0.0" \
  NODE_ENV="production" \
  RAILS_ENV="production" \
  DEBIAN_FRONTEND="noninteractive" \
  PATH="${PATH}:/opt/ruby/bin:/opt/mastodon/bin:/usr/local/bundle/bin" \
  MALLOC_CONF="narenas:2,background_thread:true,thp:never,dirty_decay_ms:1000,muzzy_decay_ms:0" \
  MASTODON_USE_LIBVIPS=true \
  MASTODON_SIDEKIQ_READY_FILENAME=sidekiq_process_has_started_and_will_begin_processing_jobs \
  GEM_HOME="/usr/local/bundle"
  

# Set default shell used for running commands
SHELL ["/bin/bash", "-o", "pipefail", "-o", "errexit", "-c"]

ARG TARGETPLATFORM

FROM cgr.dev/chainguard/ruby:latest-dev AS ruby-dev
USER root

# Resulting version string is vX.X.X-MASTODON_VERSION_PRERELEASE+MASTODON_VERSION_METADATA
# Example: v4.3.0-nightly.2023.11.09+pr-123456
# Overwrite existence of 'alpha.X' in version.rb [--build-arg MASTODON_VERSION_PRERELEASE="nightly.2023.11.09"]
ARG MASTODON_VERSION_PRERELEASE=""
# Append build metadata or fork information to version.rb [--build-arg MASTODON_VERSION_METADATA="pr-123456"]
ARG MASTODON_VERSION_METADATA=""
# Will be available as Mastodon::Version.source_commit
ARG SOURCE_COMMIT=""

# Allow Ruby on Rails to serve static files
# See: https://docs.joinmastodon.org/admin/config/#rails_serve_static_files
ARG RAILS_SERVE_STATIC_FILES="true"
# Allow to use YJIT compiler
# See: https://github.com/ruby/ruby/blob/v3_2_4/doc/yjit/yjit.md
ARG RUBY_YJIT_ENABLE="1"
# Timezone used by the Docker container and runtime, change with [--build-arg TZ=Europe/Berlin]
ARG TZ="Etc/UTC"
# Linux UID (user id) for the mastodon user, change with [--build-arg UID=1234]
ARG UID="991"
# Linux GID (group id) for the mastodon user, change with [--build-arg GID=1234]
ARG GID="991"

# Apply Mastodon build options based on options above
ENV \
  MASTODON_VERSION_PRERELEASE="${MASTODON_VERSION_PRERELEASE}" \
  MASTODON_VERSION_METADATA="${MASTODON_VERSION_METADATA}" \
  SOURCE_COMMIT="${SOURCE_COMMIT}" \
  RAILS_SERVE_STATIC_FILES=${RAILS_SERVE_STATIC_FILES} \
  RUBY_YJIT_ENABLE=${RUBY_YJIT_ENABLE} \
  TZ=${TZ}

ENV \
  BIND="0.0.0.0" \
  NODE_ENV="production" \
  RAILS_ENV="production" \
  DEBIAN_FRONTEND="noninteractive" \
  PATH="${PATH}:/opt/ruby/bin:/opt/mastodon/bin:/usr/local/bundle/bin" \
  MALLOC_CONF="narenas:2,background_thread:true,thp:never,dirty_decay_ms:1000,muzzy_decay_ms:0" \
  MASTODON_USE_LIBVIPS=true \
  MASTODON_SIDEKIQ_READY_FILENAME=sidekiq_process_has_started_and_will_begin_processing_jobs \
  GEM_HOME="/usr/local/bundle"
  

# Set default shell used for running commands
SHELL ["/bin/bash", "-o", "pipefail", "-o", "errexit", "-c"]

ARG TARGETPLATFORM

RUN echo "Target platform is $TARGETPLATFORM"

RUN echo "${TZ}" > /etc/localtime ; \
  addgroup -g "${GID}" mastodon ; \
  adduser --uid "${UID}" -G mastodon -D --home /opt/mastodon mastodon ; \
  ln -s /opt/mastodon /mastodon ;

# Set /opt/mastodon as working directory
WORKDIR /opt/mastodon

# hadolint ignore=DL3008,DL3005
RUN apk add --no-cache \
  curl \
  file \
  patchelf \
  procps \
  tini \
  tzdata

# Create temporary build layer from base image
FROM ruby-dev AS build

ARG TARGETPLATFORM

# hadolint ignore=DL3008
RUN apk add --no-cache \
  autoconf \
  automake \
  build-base \
  cmake \
  git \
  icu-dev \
  dav1d-dev \
  libexif-dev \
  expat-dev \
  gdbm-dev \
  gobject-introspection-dev \
  glib-dev \
  gmp-dev \
  libheif-dev \
  highway-dev \
  libidn-dev \
  libimagequant-dev \
  libjpeg-turbo-dev \
  lcms2-dev \
  lame-dev \
  opus-dev \
  snappy-dev \
  openssl-dev \
  libtool \
  libvorbis-dev \
  libwebp-dev \
  x264-dev \
  x265-dev \
  yaml-dev \
  meson \
  nasm \
  pkgconf \
  postgresql-dev \
  shared-mime-info \
  xz \
  xz-dev

# Create temporary bundler specific build layer from build layer
FROM build AS bundler

ARG TARGETPLATFORM

# Copy Gemfile config into working directory
COPY Gemfile* /opt/mastodon/

RUN \
  --mount=type=cache,id=gem-cache-${TARGETPLATFORM},target=/usr/local/bundle/cache/,sharing=locked \
  bundle config set --global frozen "true"; \
  bundle config set --global cache_all "false"; \
  bundle config set --local without "development test"; \
  bundle config set silence_root_warning "true"; \
  bundle install -j"$(nproc)";

# Create temporary assets build layer from build layer
FROM build AS precompiler

ARG TARGETPLATFORM

# Copy Mastodon sources into layer
COPY . /opt/mastodon/

RUN apk add --no-cache \
  nodejs \
  corepack \
  rails \
  libvips

RUN \
  corepack enable; \
  corepack prepare --activate;

# hadolint ignore=DL3008
RUN \
  --mount=type=cache,id=corepack-cache-${TARGETPLATFORM},target=/usr/local/share/.cache/corepack,sharing=locked \
  --mount=type=cache,id=yarn-cache-${TARGETPLATFORM},target=/usr/local/share/.cache/yarn,sharing=locked \
  yarn workspaces focus --production @mastodon/mastodon;

# Copy bundler packages into layer for precompiler
COPY --from=bundler /opt/mastodon /opt/mastodon/
COPY --from=bundler /usr/local/bundle/ /usr/local/bundle/

RUN \
  ldconfig; \
  SECRET_KEY_BASE_DUMMY=1 \
  bundle exec rails assets:precompile; \
  rm -fr /opt/mastodon/tmp;

# Prep final Mastodon Ruby layer
FROM ruby-dev AS mastodon-prep

COPY --from=ruby-prod / /base-chroot
RUN apk add --no-script --no-commit-hooks --no-cache --root /base-chroot bash-binsh
RUN apk add --no-cache --root /base-chroot \
  icu \
  libidn \
  libpq \
  readline \
  openssl \
  yaml \
  ffmpeg \
  libvips \
  ruby3.4-bundler \
  tini

# Smoketest media processors
RUN chroot /base-chroot vips -v; \
    chroot /base-chroot ffmpeg -version; \
    chroot /base-chroot ffprobe -version;

RUN apk del --no-script --no-commit-hooks --no-cache --root /base-chroot bash-binsh

# Try to remove perl package completely using apk del (may fail if it's a dependency)
RUN apk del --no-script --no-commit-hooks --no-cache --root /base-chroot perl || true

# Remove unneeded files from base-chroot to reduce image size
# Conservative cleanup: only remove binaries/tools that are definitely not runtime dependencies
# Note: Cannot remove codec libraries (aom, SvtAv1, rav1e, jxl, glycin) as ffmpeg/vips may depend on them
RUN rm -rf /base-chroot/usr/share/doc/* \
           /base-chroot/usr/share/man/* \
           /base-chroot/usr/lib/*.a \
           /base-chroot/usr/include/* \
           /base-chroot/usr/lib/libgtk-4.* \
           /base-chroot/usr/bin/gtk4-* \
           /base-chroot/usr/bin/glycin-* \
           /base-chroot/usr/share/gtk-4.0 \
           /base-chroot/usr/lib/libSDL2* \
           /base-chroot/usr/bin/rav1e \
           /base-chroot/usr/bin/x264 \
           /base-chroot/usr/share/glib-2.0 \
           /base-chroot/usr/share/mime

# Copy Mastodon sources for final layer
COPY . /opt/mastodon/
RUN \
  mkdir -p /opt/mastodon/public/system /opt/mastodon/tmp;\
  chown mastodon:mastodon /opt/mastodon/public/system; \
  chown -R mastodon:mastodon /opt/mastodon/tmp;


# Copy compiled assets to layer
COPY --from=precompiler /opt/mastodon/public/packs /opt/mastodon/public/packs
COPY --from=precompiler /opt/mastodon/public/assets /opt/mastodon/public/assets
# Copy bundler components to layer
COPY --from=bundler /usr/local/bundle/ /usr/local/bundle/
COPY --from=bundler /opt/mastodon/.bundle/config /opt/mastodon/.bundle/config

RUN ldconfig

# Precompile bootsnap code for faster Rails startup
RUN bundle exec bootsnap precompile --gemfile app/ lib/



FROM ruby-prod AS mastodon
COPY --from=mastodon-prep /base-chroot /

COPY --from=ruby-dev /etc/localtime /etc/localtime
COPY --from=ruby-dev /etc/passwd /etc/passwd
COPY --from=ruby-dev /etc/group /etc/group
COPY --from=ruby-dev /etc/shadow /etc/shadow

COPY --from=mastodon-prep --chown=mastodon:mastodon /opt/mastodon /opt/mastodon

# Copy compiled assets to layer
COPY --from=precompiler /opt/mastodon/public/packs /opt/mastodon/public/packs
COPY --from=precompiler /opt/mastodon/public/assets /opt/mastodon/public/assets
# Copy bundler components to layer
COPY --from=bundler /usr/local/bundle/ /usr/local/bundle/
COPY --from=bundler /opt/mastodon/.bundle/config /opt/mastodon/.bundle/config

# Set the running user for resulting container
USER mastodon

WORKDIR /opt/mastodon

# Expose default Puma ports
EXPOSE 3000
# Set container tini as default entry point
ENTRYPOINT ["/usr/bin/tini", "--"]
