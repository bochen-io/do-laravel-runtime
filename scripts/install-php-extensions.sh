#!/bin/sh
# ════════════════════════════════════════════════════════════════
# PHP Extensions Installer Script
# ════════════════════════════════════════════════════════════════
#
# This script installs PHP extensions based on values-php configuration.
# Runs during Docker build stage.
#

set -e

# Load configuration
# When running in Docker build, config is at /tmp/values-php
# Otherwise, load from root directory relative to script location
if [ -f "/tmp/values-php" ]; then
    CONFIG_FILE="/tmp/values-php"
else
    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
    ROOT_DIR="$(dirname "$SCRIPT_DIR")"
    CONFIG_FILE="${ROOT_DIR}/values-php"
fi

if [ ! -f "$CONFIG_FILE" ]; then
    echo "❌ Error: values-php not found at $CONFIG_FILE"
    exit 1
fi

# Source configuration (extract key=value pairs, ignore comments)
eval "$(grep -E '^BUILD_EXTRA_EXTENSIONS=' "$CONFIG_FILE")"

echo "🔨 Installing PHP extensions..."

# ============================================================================
# Core Extensions (always installed)
# ============================================================================

CORE_EXTENSIONS="pdo pdo_mysql pdo_pgsql pgsql zip intl mbstring curl opcache pcntl sockets exif"

echo "📦 Installing core extensions..."
echo "   Extensions: ${CORE_EXTENSIONS}"

# ============================================================================
# Optional Extensions (based on BUILD_EXTRA_EXTENSIONS)
# ============================================================================

OPTIONAL_EXTENSIONS=""
CONFIGURE_COMMANDS=""
INSTALL_REDIS=""

if [ -n "${BUILD_EXTRA_EXTENSIONS}" ]; then
    echo "📦 Processing optional extensions: ${BUILD_EXTRA_EXTENSIONS}"

    # Parse space-separated list
    for ext in ${BUILD_EXTRA_EXTENSIONS}; do
        case "$ext" in
            gd)
                echo "   ✓ Enabling GD (image processing + WEBP)"
                OPTIONAL_EXTENSIONS="${OPTIONAL_EXTENSIONS} gd"
                CONFIGURE_COMMANDS="${CONFIGURE_COMMANDS} && docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp"
                ;;
            xml)
                echo "   ✓ Enabling XML"
                OPTIONAL_EXTENSIONS="${OPTIONAL_EXTENSIONS} xml"
                ;;
            bcmath)
                echo "   ✓ Enabling BCMath (arbitrary precision math)"
                OPTIONAL_EXTENSIONS="${OPTIONAL_EXTENSIONS} bcmath"
                ;;
            redis)
                INSTALL_REDIS="yes"
                ;;
            *)
                echo "   ⚠️  Unknown extension: $ext (skipping)"
                ;;
        esac
    done
fi

# ============================================================================
# Install all extensions
# ============================================================================

ALL_EXTENSIONS="${CORE_EXTENSIONS}${OPTIONAL_EXTENSIONS}"

echo ""
echo "🔧 Installing extensions: ${ALL_EXTENSIONS}"
echo ""

# Run configure commands if any
if [ -n "${CONFIGURE_COMMANDS}" ]; then
    eval "${CONFIGURE_COMMANDS#" && "}"
fi

# Install all extensions
docker-php-ext-install -j$(nproc) ${ALL_EXTENSIONS}

echo ""
echo "✅ Core and optional extensions installed"

# ============================================================================
# PECL Extensions
# ============================================================================

echo ""
echo "🔨 Installing PECL extensions..."

# OpenSwoole (required for Laravel Octane)
if [ -n "${SWOOLE_VERSION}" ]; then
    echo "📦 Installing OpenSwoole ${SWOOLE_VERSION}"
    pecl install "openswoole-${SWOOLE_VERSION}"
    docker-php-ext-enable openswoole
    echo "✅ OpenSwoole ${SWOOLE_VERSION} installed"
else
    echo "⚠️  Warning: SWOOLE_VERSION not set, skipping OpenSwoole installation"
fi

# Redis Extension (if requested in BUILD_EXTRA_EXTENSIONS)
if [ "${INSTALL_REDIS}" = "yes" ]; then
    echo "📦 Installing Redis extension"
    pecl install redis
    docker-php-ext-enable redis
    echo "✅ Redis extension installed"
fi

# ============================================================================
# Summary
# ============================================================================

echo ""
echo "📊 Extension Installation Summary:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Core Extensions:"
echo "  ${CORE_EXTENSIONS}"
echo ""
echo "Optional Extensions:"
if [ -n "${OPTIONAL_EXTENSIONS}" ]; then
    echo "  ${OPTIONAL_EXTENSIONS}"
else
    echo "  None (all disabled in values-php)"
fi
echo ""
echo "PECL Extensions:"
PECL_LIST=""
if [ -n "${SWOOLE_VERSION}" ]; then
    PECL_LIST="openswoole-${SWOOLE_VERSION}"
fi
if [ "${INSTALL_REDIS}" = "yes" ]; then
    PECL_LIST="${PECL_LIST:+${PECL_LIST} }redis"
fi
if [ -n "${PECL_LIST}" ]; then
    echo "  ${PECL_LIST}"
else
    echo "  None"
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "✅ PHP extensions installation complete!"