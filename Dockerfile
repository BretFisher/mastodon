# syntax=docker/dockerfile:1.18

# This file is designed for production server deployment, not local development work
# For a containerized local dev environment, see: https://github.com/mastodon/mastodon/blob/main/docs/DEVELOPMENT.md#docker

# Please see https://docs.docker.com/engine/reference/builder for information about
# the extended buildx capabilities used in this file.
# Make sure multiarch TARGETPLATFORM is available for interpolation
# See: https://docs.docker.com/build/building/multi-platform/
ARG TARGETPLATFORM=${TARGETPLATFORM}
ARG BUILDPLATFORM=${BUILDPLATFORM}
ARG BASE_REGISTRY="cgr.dev/chainguard"

# Ruby image to use for base image, change with [--build-arg RUBY_VERSION="3.4.x"]
# renovate: datasource=docker depName=docker.io/ruby
ARG RUBY_VERSION="latest"
# # Node.js version to use in base image, change with [--build-arg NODE_MAJOR_VERSION="20"]
# renovate: datasource=node-version depName=node
ARG NODE_MAJOR_VERSION="latest"
# Node.js image to use for base image based on combined variables (ex: 20-trixie-slim)
FROM ${BASE_REGISTRY}/node:${NODE_MAJOR_VERSION} AS node
# Ruby image to use for base image based on combined variables (ex: 3.4.x-slim-trixie)
FROM ${BASE_REGISTRY}/ruby:${RUBY_VERSION}-dev AS ruby
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

# CG-CONVERSION: removed libjemalloc2 and wget as already in the base ruby -dev image
# hadolint ignore=DL3008,DL3005
RUN apk add --no-cache curl file patchelf procps tini tzdata
    # patchelf --add-needed libjemalloc.so.2 /usr/local/bin/ruby

# Create temporary build layer from base image
FROM ruby AS build

ARG TARGETPLATFORM

# hadolint ignore=DL3008
RUN apk add --no-cache autoconf automake build-base cmake git icu-dev dav1d-dev libexif-dev expat-dev gdbm-dev gobject-introspection-dev glib-dev gmp-dev libheif-dev highway-dev libidn-dev libimagequant-dev libjpeg-turbo-dev lcms2-dev lame-dev opus-dev snappy-dev openssl-dev libtool libvorbis-dev libwebp-dev x264-dev x265-dev yaml-dev meson nasm pkgconf postgresql-dev shared-mime-info xz xz-dev
# RUN apk add --no-cache autoconf automake build-base cmake git icu-dev libcgif-dev libdav1d-dev libexif-dev libexpat1-dev libgdbm-dev libgirepository1.0-dev libglib2.0-dev libgmp-dev libheif-dev libhwy-dev libidn-dev libimagequant-dev libjpeg62-turbo-dev liblcms2-dev libmp3lame-dev libopus-dev libsnappy-dev libspng-dev libssl3 libtiff-dev libtool libvorbis-dev libvpx-dev libwebp-dev libx264-dev libx265-dev libyaml-dev meson nasm pkgconf postgresql-dev shared-mime-info xz xz-dev

# # Create temporary libvips specific build layer from build layer
# FROM build AS libvips

# # libvips version to compile, change with [--build-arg VIPS_VERSION="8.15.2"]
# # renovate: datasource=github-releases depName=libvips packageName=libvips/libvips
# ARG VIPS_VERSION=8.17.2
# # libvips download URL, change with [--build-arg VIPS_URL="https://github.com/libvips/libvips/releases/download"]
# ARG VIPS_URL=https://github.com/libvips/libvips/releases/download

# WORKDIR /usr/local/libvips/src
# # Download and extract libvips source code
# ADD ${VIPS_URL}/v${VIPS_VERSION}/vips-${VIPS_VERSION}.tar.xz /usr/local/libvips/src/
# RUN tar -x -f vips-${VIPS_VERSION}.tar.xz ;

# WORKDIR /usr/local/libvips/src/vips-${VIPS_VERSION}

# # Configure and compile libvips
# RUN \
#   meson setup build --prefix /usr/local/libvips --libdir=lib -Ddeprecated=false -Dintrospection=disabled -Dmodules=disabled -Dexamples=false; \
#   cd build; \
#   ninja; \
#   ninja install;

# # Create temporary ffmpeg specific build layer from build layer
# FROM build AS ffmpeg

# # ffmpeg version to compile, change with [--build-arg FFMPEG_VERSION="7.0.x"]
# # renovate: datasource=repology depName=ffmpeg packageName=openpkg_current/ffmpeg
# ARG FFMPEG_VERSION=8.0
# # ffmpeg download URL, change with [--build-arg FFMPEG_URL="https://ffmpeg.org/releases"]
# ARG FFMPEG_URL=https://ffmpeg.org/releases

# WORKDIR /usr/local/ffmpeg/src
# # Download and extract ffmpeg source code
# ADD ${FFMPEG_URL}/ffmpeg-${FFMPEG_VERSION}.tar.xz /usr/local/ffmpeg/src/
# RUN tar -x -f ffmpeg-${FFMPEG_VERSION}.tar.xz ;

# WORKDIR /usr/local/ffmpeg/src/ffmpeg-${FFMPEG_VERSION}

# # Configure and compile ffmpeg
# RUN \
#   ./configure \
#   --prefix=/usr/local/ffmpeg \
#   --toolchain=hardened \
#   --disable-debug \
#   --disable-devices \
#   --disable-doc \
#   --disable-ffplay \
#   --disable-network \
#   --disable-static \
#   --enable-ffmpeg \
#   --enable-ffprobe \
#   --enable-gpl \
#   --enable-libdav1d \
#   --enable-libmp3lame \
#   --enable-libopus \
#   --enable-libsnappy \
#   --enable-libvorbis \
#   --disable-libvpx \
#   --enable-libwebp \
#   --enable-libx264 \
#   --enable-libx265 \
#   --enable-shared \
#   --enable-version3 \
#   ; \
#   make -j$(nproc); \
#   make install;

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

# # Copy Node.js binaries/libraries into layer
# COPY --from=node /usr/local/bin /usr/local/bin
# COPY --from=node /usr/local/lib /usr/local/lib
RUN apk add --no-cache nodejs corepack rails libvips

RUN \
  corepack enable; \
  corepack prepare --activate;

# hadolint ignore=DL3008
RUN \
  --mount=type=cache,id=corepack-cache-${TARGETPLATFORM},target=/usr/local/share/.cache/corepack,sharing=locked \
  --mount=type=cache,id=yarn-cache-${TARGETPLATFORM},target=/usr/local/share/.cache/yarn,sharing=locked \
  yarn workspaces focus --production @mastodon/mastodon;

# Copy libvips components into layer for precompiler
# COPY --from=libvips /usr/local/libvips/bin /usr/local/bin
# COPY --from=libvips /usr/local/libvips/lib /usr/local/lib
# Copy bundler packages into layer for precompiler
COPY --from=bundler /opt/mastodon /opt/mastodon/
COPY --from=bundler /usr/local/bundle/ /usr/local/bundle/

RUN \
  ldconfig; \
  SECRET_KEY_BASE_DUMMY=1 \
  bundle exec rails assets:precompile; \
  rm -fr /opt/mastodon/tmp;

# Prep final Mastodon Ruby layer
FROM ruby AS mastodon

ARG TARGETPLATFORM

# hadolint ignore=DL3008
RUN apk add --no-cache \
  expat \
  glib \
  icu \
  libidn \
  libpq \
  readline \
  openssl \
  yaml 
    # patchelf --add-needed libjemalloc.so.2 /usr/local/bin/ruby
# RUN apk add --no-cache dav1d libexif expat glib libheif highway icu libidn2 libimagequant libjpeg-turbo lcms2 lame opus libpq readline snappy openssl libtheora tiff libvorbis libvorbis libvorbis libwebp libwebp libwebp x264 x265 yaml ruby3.4-bundler
# RUN apk add --no-cache libcgif0 libdav1d7 libexif12 libexpat1 libglib2.0-0t64 libheif1 libhwy1t64 libicu76 libidn12 libimagequant0 libjpeg62-turbo liblcms2-2 libmp3lame0 libopencore-amrnb0 libopencore-amrwb0 libopus0 libpq libreadline8t64 libsnappy1v5 libspng0 libssl3t64 libtheora0 libtiff6 libvorbis0a libvorbisenc2 libvorbisfile3 libvpx9 libwebp7 libwebpdemux2 libwebpmux3 libx264-164 libx265-215 libyaml-0-2

# Copy Mastodon sources into final layer
COPY . /opt/mastodon/

# Copy compiled assets to layer
COPY --from=precompiler /opt/mastodon/public/packs /opt/mastodon/public/packs
COPY --from=precompiler /opt/mastodon/public/assets /opt/mastodon/public/assets
# Copy bundler components to layer
COPY --from=bundler /usr/local/bundle/ /usr/local/bundle/
COPY --from=bundler /opt/mastodon/.bundle/config /opt/mastodon/.bundle/config
# Copy libvips components to layer
# COPY --from=libvips /usr/local/libvips/bin /usr/local/bin
# COPY --from=libvips /usr/local/libvips/lib /usr/local/lib
# Copy ffpmeg components to layer
# COPY --from=ffmpeg /usr/local/ffmpeg/bin /usr/local/bin
# COPY --from=ffmpeg /usr/local/ffmpeg/lib /usr/local/lib

RUN apk add --no-cache ffmpeg libvips

RUN \
  ldconfig; \
  vips -v; \
  ffmpeg -version; \
  ffprobe -version;

RUN \
  bundle exec bootsnap precompile --gemfile app/ lib/;

RUN \
  mkdir -p /opt/mastodon/public/system; \
  chown mastodon:mastodon /opt/mastodon/public/system; \
  chown -R mastodon:mastodon /opt/mastodon/tmp;

# Set the running user for resulting container
USER mastodon
# Expose default Puma ports
EXPOSE 3000
# Set container tini as default entry point
ENTRYPOINT ["/usr/bin/tini", "--"]
