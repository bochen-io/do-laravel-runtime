# ════════════════════════════════════════════════════════════════
# DigitalOcean Laravel Runtime - Production-Ready Base Image
# ════════════════════════════════════════════════════════════════
#
# Optimized base image for Laravel Octane applications with:
# - PHP CLI (Alpine Linux) - Version set in 'versions' file (8.4 and 8.5 supported)
# - OpenSwoole - High-performance async runtime - Version set in 'versions' file
# - Composer - Dependency management - Version set in 'versions' file
# - Supervisord - Process control system
# - PostgreSQL support - Optimized for DO managed databases
#
# Usage:
#   FROM ghcr.io/bochen-io/do-laravel-runtime:latest    # PHP 8.4
#   FROM ghcr.io/bochen-io/do-laravel-runtime:php8.5    # PHP 8.5
#
# Build with custom versions (or use ./build.sh --php-version 8.5-cli-alpine):
#   docker build --build-arg PHP_VERSION=8.5-cli-alpine \
#                --build-arg SWOOLE_VERSION=26.2.0 \
#                --build-arg COMPOSER_VERSION=2 \
#                -t my-runtime .
#
# ════════════════════════════════════════════════════════════════

# ============================================================================
# Build Stage - Compile PHP extensions and OpenSwoole
# ============================================================================

# Build arguments (set in versions file)
ARG PHP_VERSION
ARG SWOOLE_VERSION
ARG COMPOSER_VERSION
ARG NODE_VERSION

FROM php:${PHP_VERSION} AS builder

# Re-declare build arguments for this stage
ARG SWOOLE_VERSION

# Install build dependencies
RUN apk add --no-cache \
    autoconf \
    g++ \
    make \
    gcc \
    libc-dev \
    pkgconfig \
    linux-headers \
    libpng-dev \
    libjpeg-turbo-dev \
    freetype-dev \
    libwebp-dev \
    libzip-dev \
    postgresql-dev \
    icu-dev \
    oniguruma-dev \
    libxml2-dev \
    curl-dev

# Copy configuration and installation scripts
COPY values-php /tmp/values-php
COPY scripts/install-php-extensions.sh /tmp/install-php-extensions.sh

# Install PHP extensions using script
RUN chmod +x /tmp/install-php-extensions.sh && \
    /tmp/install-php-extensions.sh

# ============================================================================
# Composer Stage - Extract composer binary
# ============================================================================

ARG COMPOSER_VERSION
FROM composer:${COMPOSER_VERSION} AS composer

# ============================================================================
# Node Stage - Node.js binary source
# ============================================================================
#
# Alpine's repository only carries whatever Node major the base release
# happens to ship, so the major is pinned via the official Node image and
# a future Alpine bump cannot move it silently.
#
ARG NODE_VERSION
FROM node:${NODE_VERSION}-alpine AS node

# ============================================================================
# Final Stage - Minimal runtime image
# ============================================================================

# Re-declare build arguments for final stage
ARG PHP_VERSION
ARG SWOOLE_VERSION
ARG COMPOSER_VERSION
ARG NODE_VERSION

FROM php:${PHP_VERSION}

# Labels with dynamic versions
LABEL description="Production-ready PHP ${PHP_VERSION} + OpenSwoole ${SWOOLE_VERSION} runtime for Laravel Octane on DigitalOcean Apps"
LABEL org.opencontainers.image.source="https://github.com/bochen-io/do-laravel-runtime"
LABEL php.version="${PHP_VERSION}"
LABEL swoole.version="${SWOOLE_VERSION}"
LABEL composer.version="${COMPOSER_VERSION}"
LABEL node.version="${NODE_VERSION}"
# Install only runtime dependencies
RUN apk add --no-cache \
    # Image libraries \
    libpng \
    libjpeg-turbo \
    freetype \
    libwebp \
    # Archive support \
    libzip \
    # Database support \
    postgresql-client \
    postgresql-libs \
    # Internationalization \
    icu-libs \
    # String processing \
    oniguruma \
    # XML processing \
    libxml2 \
    # Network \
    curl \
    # Node.js runtime dependencies \
    libstdc++ \
    # Version control \
    git \
    # Utilities \
    unzip \
    wget \
    bash \
    ca-certificates

# Install supervisor from edge (separate to avoid bash dependency conflicts)
RUN apk add --no-cache --repository=https://dl-cdn.alpinelinux.org/alpine/edge/main supervisor

# Copy PHP extensions from builder
COPY --from=builder /usr/local/lib/php/extensions/ /usr/local/lib/php/extensions/
COPY --from=builder /usr/local/etc/php/conf.d/ /usr/local/etc/php/conf.d/

# Copy Composer from composer stage
COPY --from=composer /usr/bin/composer /usr/bin/composer

# Copy Node.js + npm from node stage (frontend asset building)
COPY --from=node /usr/local/bin/node /usr/local/bin/node
COPY --from=node /usr/local/lib/node_modules/npm /usr/local/lib/node_modules/npm

# Restore the npm/npx entrypoints and add pnpm
RUN ln -s ../lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm && \
    ln -s ../lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx && \
    npm install -g pnpm && \
    npm cache clean --force && \
    node -v && npm -v && pnpm -v

# Copy configuration script and configure PHP
COPY values-php /tmp/values-php
COPY scripts/configure-php.sh /tmp/configure-php.sh
RUN chmod +x /tmp/configure-php.sh && \
    /tmp/configure-php.sh && \
    rm /tmp/values-php /tmp/configure-php.sh

# Create application directory
WORKDIR /var/www

# Create supervisor configuration directory
RUN mkdir -p /etc/supervisor/conf.d

# Expose common ports
EXPOSE 8000 5173

# Default command
CMD ["/bin/sh"]
