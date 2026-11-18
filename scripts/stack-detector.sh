#!/usr/bin/env bash
# Project Technology Stack & Capability Detector (Bash/POSIX)

TARGET_DIR="${1:-.}"

# Colors
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
WHITE='\033[1;37m'
GRAY='\033[0;37m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

echo -e "${CYAN}=== Detecting Technology Stack & Performance Capabilities ===${NC}"
echo -e "${GRAY}Target Directory: ${TARGET_DIR}${NC}\n"

COMPOSER_PATH="${TARGET_DIR}/composer.json"
PACKAGE_PATH="${TARGET_DIR}/package.json"
ENV_PATH="${TARGET_DIR}/.env"
MODULES_PATH="${TARGET_DIR}/Modules"

# 1. Environment & Infrastructure Check
if [ -f "$ENV_PATH" ]; then
    echo -e "${GREEN}[Infrastructure - .env detected]${NC}"

    # Cache Driver
    CACHE_DRIVER=$(grep -E '^(CACHE_STORE|CACHE_DRIVER)=' "$ENV_PATH" | head -n 1 | cut -d'=' -f2 | tr -d '"'\'' ')
    if [ -n "$CACHE_DRIVER" ]; then
        echo -e "${WHITE}  * Cache Driver: ${CACHE_DRIVER}${NC}"
        if [[ "$CACHE_DRIVER" =~ (redis|memcached) ]]; then
            echo -e "${GRAY}    - Cache::tags() & atomic locks: Supported${NC}"
        else
            echo -e "${YELLOW}    - Warning: Cache::tags() NOT supported on '${CACHE_DRIVER}' (use versioned keys instead)${NC}"
        fi
    fi

    # DB Connection
    DB_CONN=$(grep -E '^DB_CONNECTION=' "$ENV_PATH" | head -n 1 | cut -d'=' -f2 | tr -d '"'\'' ')
    if [ -n "$DB_CONN" ]; then
        echo -e "${WHITE}  * Database Connection: ${DB_CONN}${NC}"
        if [[ "$DB_CONN" =~ pgsql ]]; then
            echo -e "${GRAY}    - PostgreSQL: Use CREATE INDEX CONCURRENTLY with \$withinTransaction = false in migrations${NC}"
        elif [[ "$DB_CONN" =~ mysql ]]; then
            echo -e "${GRAY}    - MySQL: Use ALGORITHM=INPLACE, LOCK=NONE for online indexing${NC}"
        fi
    fi
fi

# 2. Backend Check (composer.json)
if [ -f "$COMPOSER_PATH" ]; then
    echo -e "\n${GREEN}[Backend - composer.json detected]${NC}"

    # Laravel Framework
    LARAVEL_VER=$(grep -E '"laravel/framework"' "$COMPOSER_PATH" | head -n 1 | sed -E 's/.*"laravel\/framework"\s*:\s*"([^"]+)".*/\1/')
    if [ -n "$LARAVEL_VER" ]; then
        echo -e "${WHITE}  * Laravel Framework: ${LARAVEL_VER}${NC}"
        echo -e "${GRAY}    - Model::preventLazyLoading: Supported${NC}"
        echo -e "${GRAY}    - withExists / withSum / withAvg / lazyById: Supported${NC}"
        
        # Check Laravel version >= 11
        MAJOR_VER=$(echo "$LARAVEL_VER" | grep -oE '[0-9]+' | head -n 1)
        if [ -n "$MAJOR_VER" ] && [ "$MAJOR_VER" -ge 11 ]; then
            echo -e "${GRAY}    - Laravel 11+ once() helper: Supported for request memoization${NC}"
        fi
    fi

    # Inertia Laravel Adapter
    INERTIA_VER=$(grep -E '"inertiajs/inertia-laravel"' "$COMPOSER_PATH" | head -n 1 | sed -E 's/.*"inertiajs\/inertia-laravel"\s*:\s*"([^"]+)".*/\1/')
    if [ -n "$INERTIA_VER" ]; then
        echo -e "${WHITE}  * Inertia Laravel Adapter: ${INERTIA_VER}${NC}"
        IN_MAJOR=$(echo "$INERTIA_VER" | grep -oE '[0-9]+' | head -n 1)
        if [ -n "$IN_MAJOR" ] && [ "$IN_MAJOR" -ge 3 ]; then
            echo -e "${GREEN}    - Inertia v${IN_MAJOR} Detected: Deferred Props & Polling ENABLED${NC}"
            echo -e "${CYAN}    - IMPORTANT: Inertia::lazy() REMOVED; use Inertia::optional()${NC}"
        elif [ -n "$IN_MAJOR" ] && [ "$IN_MAJOR" -eq 2 ]; then
            echo -e "${GREEN}    - Inertia v2 Detected: Deferred Props & Polling ENABLED${NC}"
        else
            echo -e "${YELLOW}    - Inertia v1 Detected: Deferred Props NOT supported (Use lazy/partial reload)${NC}"
        fi
    fi

    # Spatie MediaLibrary
    SPATIE_VER=$(grep -E '"spatie/laravel-medialibrary"' "$COMPOSER_PATH" | head -n 1 | sed -E 's/.*"spatie\/laravel-medialibrary"\s*:\s*"([^"]+)".*/\1/')
    if [ -n "$SPATIE_VER" ]; then
        echo -e "${WHITE}  * Spatie MediaLibrary: ${SPATIE_VER}${NC}"
        echo -e "${GRAY}    - Ensure conversions are marked ->queued()${NC}"
    fi

    # Modular Monolith
    if grep -q '"nwidart/laravel-modules"' "$COMPOSER_PATH" || [ -d "$MODULES_PATH" ]; then
        echo -e "${MAGENTA}  * Modular Architecture Detected${NC}"
        echo -e "${GRAY}    - Anti-pattern scanner will include Modules/ directory${NC}"
    fi
else
    echo -e "\n${GRAY}No composer.json found in ${TARGET_DIR}${NC}"
fi

# 3. Frontend Check (package.json)
if [ -f "$PACKAGE_PATH" ]; then
    echo -e "\n${GREEN}[Frontend - package.json detected]${NC}"

    # Vue
    VUE_VER=$(grep -E '"vue"' "$PACKAGE_PATH" | head -n 1 | sed -E 's/.*"vue"\s*:\s*"([^"]+)".*/\1/')
    if [ -n "$VUE_VER" ]; then
        echo -e "${WHITE}  * Vue: ${VUE_VER}${NC}"
        echo -e "${GRAY}    - shallowRef, markRaw, defineAsyncComponent, v-memo: Supported${NC}"
    fi

    # Inertia Vue3 / React
    INERTIA_CLIENT=$(grep -E '"@inertiajs/vue3"' "$PACKAGE_PATH" | head -n 1 | sed -E 's/.*"@inertiajs\/vue3"\s*:\s*"([^"]+)".*/\1/')
    if [ -n "$INERTIA_CLIENT" ]; then
        echo -e "${WHITE}  * @inertiajs/vue3: ${INERTIA_CLIENT}${NC}"
        IN_C_MAJOR=$(echo "$INERTIA_CLIENT" | grep -oE '[0-9]+' | head -n 1)
        if [ -n "$IN_C_MAJOR" ] && [ "$IN_C_MAJOR" -ge 2 ]; then
            echo -e "${GRAY}    - <Deferred> component with skeleton fallback: Supported${NC}"
        fi
    fi

    # Vite
    VITE_VER=$(grep -E '"vite"' "$PACKAGE_PATH" | head -n 1 | sed -E 's/.*"vite"\s*:\s*"([^"]+)".*/\1/')
    if [ -n "$VITE_VER" ]; then
        echo -e "${WHITE}  * Vite: ${VITE_VER} (Code splitting via dynamic import supported)${NC}"
    fi
else
    echo -e "\n${GRAY}No package.json found in ${TARGET_DIR}${NC}"
fi

echo -e "\n${CYAN}=== Stack Detection Complete ===${NC}"
