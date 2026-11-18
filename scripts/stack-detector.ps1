# Project Technology Stack & Capability Detector (PowerShell)
param (
    [string]$TargetDir = "."
)

Write-Host "=== Detecting Technology Stack & Performance Capabilities ===" -ForegroundColor Cyan
Write-Host "Target Directory: $TargetDir`n" -ForegroundColor DarkGray

$composerPath = Join-Path $TargetDir "composer.json"
$packagePath = Join-Path $TargetDir "package.json"
$envPath = Join-Path $TargetDir ".env"
$modulesPath = Join-Path $TargetDir "Modules"

# 1. Environment & Infrastructure Check
if (Test-Path $envPath) {
    Write-Host "[Infrastructure - .env detected]" -ForegroundColor Green
    $envContent = Get-Content $envPath -Raw

    # Cache Driver
    if ($envContent -match 'CACHE_(?:STORE|DRIVER)\s*=\s*([^\r\n#]+)') {
        $cacheDriver = $matches[1].Trim()
        Write-Host "  * Cache Driver: $cacheDriver" -ForegroundColor White
        if ($cacheDriver -match 'redis|memcached') {
            Write-Host "    - Cache::tags() & atomic locks: Supported" -ForegroundColor Gray
        } else {
            Write-Host "    - Warning: Cache::tags() NOT supported on '$cacheDriver' (use versioned keys instead)" -ForegroundColor Yellow
        }
    }

    # DB Connection
    if ($envContent -match 'DB_CONNECTION\s*=\s*([^\r\n#]+)') {
        $dbConn = $matches[1].Trim()
        Write-Host "  * Database Connection: $dbConn" -ForegroundColor White
        if ($dbConn -match 'pgsql') {
            Write-Host "    - PostgreSQL: Use CREATE INDEX CONCURRENTLY with `$withinTransaction = false in migrations" -ForegroundColor Gray
        } elseif ($dbConn -match 'mysql') {
            Write-Host "    - MySQL: Use ALGORITHM=INPLACE, LOCK=NONE for online indexing" -ForegroundColor Gray
        }
    }
}

# 2. Backend Check (composer.json)
if (Test-Path $composerPath) {
    Write-Host "`n[Backend - composer.json detected]" -ForegroundColor Green
    $composer = Get-Content $composerPath -Raw | ConvertFrom-Json
    $req = $composer.require

    # Check Laravel Framework
    if ($req.'laravel/framework') {
        $v = $req.'laravel/framework'
        Write-Host "  * Laravel Framework: $v" -ForegroundColor White
        Write-Host "    - Model::preventLazyLoading: Supported" -ForegroundColor Gray
        Write-Host "    - withExists / withSum / withAvg / lazyById: Supported" -ForegroundColor Gray

        if ($v -match '(\d+)\.') {
            $laravelMajor = [int]$matches[1]
            if ($laravelMajor -ge 11) {
                Write-Host "    - Laravel 11+ once() helper: Supported for request memoization" -ForegroundColor Gray
            }
        }
    }

    # Check Inertia Laravel Adapter
    if ($req.'inertiajs/inertia-laravel') {
        $v = $req.'inertiajs/inertia-laravel'
        Write-Host "  * Inertia Laravel Adapter: $v" -ForegroundColor White

        if ($v -match '(\d+)\.') {
            $inMajor = [int]$matches[1]
            if ($inMajor -ge 3) {
                Write-Host "    - Inertia v$inMajor Detected: Deferred Props & Polling ENABLED" -ForegroundColor Green
                Write-Host "    - IMPORTANT: Inertia::lazy() REMOVED; use Inertia::optional()" -ForegroundColor Cyan
            } elseif ($inMajor -eq 2) {
                Write-Host "    - Inertia v2 Detected: Deferred Props & Polling ENABLED" -ForegroundColor Green
            } else {
                Write-Host "    - Inertia v1 Detected: Deferred Props NOT supported (Use lazy/partial reload)" -ForegroundColor Yellow
            }
        } else {
            Write-Host "    - Inertia version pattern unrecognized: $v" -ForegroundColor DarkGray
        }
    }

    # Check Spatie MediaLibrary
    if ($req.'spatie/laravel-medialibrary') {
        Write-Host "  * Spatie MediaLibrary: $($req.'spatie/laravel-medialibrary')" -ForegroundColor White
        Write-Host "    - Ensure conversions are marked ->queued()" -ForegroundColor Gray
    }

    # Modular Monolith Check
    if ($req.'nwidart/laravel-modules' -or (Test-Path $modulesPath)) {
        Write-Host "  * Modular Architecture Detected" -ForegroundColor Magenta
        Write-Host "    - Anti-pattern scanner will include Modules/ directory" -ForegroundColor Gray
    }
} else {
    Write-Host "`nNo composer.json found in $TargetDir" -ForegroundColor DarkGray
}

# 3. Frontend Check (package.json)
if (Test-Path $packagePath) {
    Write-Host "`n[Frontend - package.json detected]" -ForegroundColor Green
    $pkg = Get-Content $packagePath -Raw | ConvertFrom-Json
    $deps = $pkg.dependencies
    $devDeps = $pkg.devDependencies

    # Helper function to get dependency version
    function Get-DepVersion($name) {
        if ($deps -and $deps.$name) { return $deps.$name }
        if ($devDeps -and $devDeps.$name) { return $devDeps.$name }
        return $null
    }

    # Vue
    $vueV = Get-DepVersion "vue"
    if ($vueV) {
        Write-Host "  * Vue: $vueV" -ForegroundColor White
        Write-Host "    - shallowRef, markRaw, defineAsyncComponent, v-memo: Supported" -ForegroundColor Gray
    }

    # Inertia Frontend
    $inVue = Get-DepVersion "@inertiajs/vue3"
    $inReact = Get-DepVersion "@inertiajs/react"
    if ($inVue) {
        Write-Host "  * @inertiajs/vue3: $inVue" -ForegroundColor White
        if ($inVue -match '(\d+)\.') {
            $inClientMajor = [int]$matches[1]
            if ($inClientMajor -ge 2) {
                Write-Host "    - <Deferred> component with skeleton fallback: Supported" -ForegroundColor Gray
            }
        }
    } elseif ($inReact) {
        Write-Host "  * @inertiajs/react: $inReact" -ForegroundColor White
    }

    # Vite
    $viteV = Get-DepVersion "vite"
    if ($viteV) {
        Write-Host "  * Vite: $viteV (Code splitting via dynamic import supported)" -ForegroundColor White
    }
} else {
    Write-Host "`nNo package.json found in $TargetDir" -ForegroundColor DarkGray
}

Write-Host "`n=== Stack Detection Complete ===" -ForegroundColor Cyan
