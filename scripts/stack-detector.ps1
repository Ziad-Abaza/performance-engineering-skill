# Project Technology Stack & Capability Detector (PowerShell)
param (
    [string]$TargetDir = "."
)

Write-Host "=== Detecting Technology Stack & Performance Capabilities ===" -ForegroundColor Cyan

$composerPath = Join-Path $TargetDir "composer.json"
$packagePath = Join-Path $TargetDir "package.json"

if (Test-Path $composerPath) {
    Write-Host "`n[Backend - composer.json detected]" -ForegroundColor Green
    $composer = Get-Content $composerPath -Raw | ConvertFrom-Json
    $req = $composer.require

    # Check Laravel Framework
    if ($req.'laravel/framework') {
        $v = $req.'laravel/framework'
        Write-Host "  * Laravel Framework: $v" -ForegroundColor White
        Write-Host "    - Model::preventLazyLoading: Supported" -ForegroundColor Gray
        Write-Host "    - withExists / lazyById: Supported" -ForegroundColor Gray
    }

    # Check Inertia Laravel Adapter
    if ($req.'inertiajs/inertia-laravel') {
        $v = $req.'inertiajs/inertia-laravel'
        Write-Host "  * Inertia Laravel Adapter: $v" -ForegroundColor White
        if ($v -match 'v?2\.') {
            Write-Host "    - Inertia v2 Detected: Deferred Props & Polling ENABLED" -ForegroundColor Green
        } else {
            Write-Host "    - Inertia v1 Detected: Deferred Props NOT supported (Use lazy/partial reload)" -ForegroundColor Yellow
        }
    }

    # Check Spatie MediaLibrary
    if ($req.'spatie/laravel-medialibrary') {
        Write-Host "  * Spatie MediaLibrary: $($req.'spatie/laravel-medialibrary')" -ForegroundColor White
        Write-Host "    - Check that conversions are marked ->queued()" -ForegroundColor Gray
    }
} else {
    Write-Host "`nNo composer.json found in $TargetDir" -ForegroundColor DarkGray
}

if (Test-Path $packagePath) {
    Write-Host "`n[Frontend - package.json detected]" -ForegroundColor Green
    $pkg = Get-Content $packagePath -Raw | ConvertFrom-Json
    $deps = $pkg.dependencies
    $devDeps = $pkg.devDependencies

    # Vue
    $vueV = if ($deps.vue) { $deps.vue } elseif ($devDeps.vue) { $devDeps.vue } else { $null }
    if ($vueV) {
        Write-Host "  * Vue: $vueV" -ForegroundColor White
        Write-Host "    - shallowRef, markRaw, defineAsyncComponent: Supported" -ForegroundColor Gray
    }

    # Inertia Vue3
    $inV = if ($deps.'@inertiajs/vue3') { $deps.'@inertiajs/vue3' } elseif ($devDeps.'@inertiajs/vue3') { $devDeps.'@inertiajs/vue3' } else { $null }
    if ($inV) {
        Write-Host "  * @inertiajs/vue3: $inV" -ForegroundColor White
    }
} else {
    Write-Host "`nNo package.json found in $TargetDir" -ForegroundColor DarkGray
}

Write-Host "`n=== Stack Detection Complete ===" -ForegroundColor Cyan
