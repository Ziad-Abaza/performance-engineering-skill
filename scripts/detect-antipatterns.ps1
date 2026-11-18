# Performance Anti-Pattern Scanner for Laravel, Inertia & Vue 3 (PowerShell)
param (
    [string]$TargetDir = "."
)

Write-Host "=== Scanning for Performance Anti-Patterns in: $TargetDir ===" -ForegroundColor Cyan

# Directories to strictly exclude from all scans
$excludedRegex = '[\\/](vendor|node_modules|\.git|storage|dist|public|bootstrap|tests)[\\/]'

# Gather valid search root directories
$topDirs = Get-ChildItem -Path $TargetDir -Directory | Where-Object { 
    $_.Name -notin @('vendor', 'node_modules', '.git', 'storage', 'dist', 'public', 'bootstrap', 'tests')
} | ForEach-Object { $_.FullName }

if (-not $topDirs) {
    $topDirs = @($TargetDir)
}

Write-Host "Searching application paths (excluding vendor, node_modules, storage, etc.)..." -ForegroundColor DarkGray

# Collect application PHP files
$phpFiles = Get-ChildItem -Path $topDirs -Recurse -Include *.php -File -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notmatch $excludedRegex -and $_.Name -notmatch 'Test\.php$' }

# Collect application Vue/JS/TS files
$frontendFiles = Get-ChildItem -Path $topDirs -Recurse -Include *.vue,*.js,*.ts -File -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notmatch $excludedRegex }

# 1. Database Queries Inside Loops
Write-Host "`n[1] Scanning for queries inside loops (foreach/while)..." -ForegroundColor Yellow
$loopMatches = $phpFiles | Select-String -Pattern '(foreach|while)\s*\(.*?\)\s*\{' -Context 0, 6
$loopCount = 0
foreach ($match in $loopMatches) {
    if ($match.Context.PostContext -match '::(find|where|first|create|update)\(' -or $match.Context.PostContext -match '->(save|update|delete)\(') {
        $loopCount++
        $relPath = $match.Path.Replace((Resolve-Path $TargetDir).Path, '').TrimStart('\/')
        Write-Host "  [!] Potential N+1 or Loop Query: $relPath : $($match.LineNumber)" -ForegroundColor Red
        Write-Host "      $($match.Line.Trim())" -ForegroundColor Gray
    }
}
if ($loopCount -eq 0) { Write-Host "  No raw loop queries detected." -ForegroundColor DarkGray }

# 2. Dangerous chunk() usage with updates
Write-Host "`n[2] Scanning for chunk() with updates (should be chunkById)..." -ForegroundColor Yellow
$chunkMatches = $phpFiles | Select-String -Pattern '->chunk\(' -Context 0, 10
$chunkCount = 0
foreach ($match in $chunkMatches) {
    if ($match.Context.PostContext -match '->(update|save|delete)\(') {
        $chunkCount++
        $relPath = $match.Path.Replace((Resolve-Path $TargetDir).Path, '').TrimStart('\/')
        Write-Host "  [!] Dangerous chunk() update: $relPath : $($match.LineNumber) (Use chunkById instead)" -ForegroundColor Red
    }
}
if ($chunkCount -eq 0) { Write-Host "  No dangerous chunk() updates detected." -ForegroundColor DarkGray }

# 3. Model $appends with potential N+1 (supports app/Models, Modules/*/Entities, src/Domain)
Write-Host "`n[3] Scanning for Model `$appends attributes..." -ForegroundColor Yellow
$nonModelDirRegex = '[\\/](Controllers|Requests|Middleware|Jobs|Listeners|Console|Commands|Providers|Exceptions|Mail|Notifications|Events|Policies|Rules|Database|Migrations|Routes|config|resources|lang)[\\/]'
$modelFiles = $phpFiles | Where-Object {
    $_.FullName -match '[\\/](Models|Entities|Domain)[\\/]' -or
    (
        $_.FullName -notmatch $nonModelDirRegex -and
        (Get-Content $_.FullName -TotalCount 25 -ErrorAction SilentlyContinue | Select-String -Pattern 'extends\s+Model')
    )
}
$appendsMatches = $modelFiles | Select-String -Pattern 'protected\s+\$appends\s*='
$appendsCount = 0
foreach ($match in $appendsMatches) {
    $appendsCount++
    $relPath = $match.Path.Replace((Resolve-Path $TargetDir).Path, '').TrimStart('\/')
    Write-Host "  [i] Model with `$appends: $relPath : $($match.LineNumber)" -ForegroundColor Magenta
    Write-Host "      Verify accessors do not query relationships or use withSum/withCount subqueries instead" -ForegroundColor DarkGray
}
if ($appendsCount -eq 0) { Write-Host "  No Model `$appends detected." -ForegroundColor DarkGray }

# 4. Unbounded SELECT * or all()
Write-Host "`n[4] Scanning for unbounded Model::all() calls..." -ForegroundColor Yellow
$allMatches = $phpFiles | Select-String -Pattern '[A-Z]\w+::all\(\)'
$allCount = 0
foreach ($match in $allMatches) {
    $allCount++
    $relPath = $match.Path.Replace((Resolve-Path $TargetDir).Path, '').TrimStart('\/')
    Write-Host "  [!] Unbounded all(): $relPath : $($match.LineNumber) (Use paginate() or select())" -ForegroundColor Red
}
if ($allCount -eq 0) { Write-Host "  No unbounded all() detected." -ForegroundColor DarkGray }

# 5. Inertia API Misuse (chained ->group() or Inertia::lazy in v3)
Write-Host "`n[5] Scanning for Inertia.js API anti-patterns..." -ForegroundColor Yellow
$inertiaCount = 0
foreach ($file in $phpFiles) {
    $content = Get-Content $file.FullName -Raw -ErrorAction SilentlyContinue
    if (-not $content) { continue }
    $relPath = $file.FullName.Replace((Resolve-Path $TargetDir).Path, '').TrimStart('\/')

    if ($content -match 'Inertia::defer[\s\S]*?->group\(') {
        $inertiaCount++
        Write-Host "  [!] Chained ->group() bug on defer: $relPath" -ForegroundColor Red
        Write-Host "      Inertia::defer(`$fn, 'group_name') takes the group as 2nd parameter, not a chained method" -ForegroundColor Gray
    }

    if ($content -match 'Inertia::lazy\(') {
        $inertiaCount++
        Write-Host "  [!] Inertia::lazy() detected: $relPath" -ForegroundColor Yellow
        Write-Host "      Inertia::lazy() is removed in Inertia v3; replace with Inertia::optional()" -ForegroundColor Gray
    }
}
if ($inertiaCount -eq 0) { Write-Host "  No Inertia API anti-patterns detected." -ForegroundColor DarkGray }

# 6. PostgreSQL Concurrent Indexing in Transactions
Write-Host "`n[6] Scanning PostgreSQL migration safe indexing..." -ForegroundColor Yellow
$migrationFiles = $phpFiles | Where-Object { $_.FullName -match '[\\/]migrations[\\/]' }
$pgMigrationCount = 0
foreach ($file in $migrationFiles) {
    $content = Get-Content $file.FullName -Raw -ErrorAction SilentlyContinue
    $relPath = $file.FullName.Replace((Resolve-Path $TargetDir).Path, '').TrimStart('\/')

    if ($content -match 'CREATE\s+INDEX\s+CONCURRENTLY' -and $content -notmatch '\$withinTransaction\s*=\s*false') {
        $pgMigrationCount++
        Write-Host "  [!] Postgres Concurrent Index missing `$withinTransaction = false: $relPath" -ForegroundColor Red
        Write-Host "      Postgres transactions block CONCURRENTLY. Add: public `$withinTransaction = false;" -ForegroundColor Gray
    }

    if ($content -match '(public|protected)\s+bool\s+\$withinTransaction') {
        $pgMigrationCount++
        Write-Host "  [!] Typed `$withinTransaction property (PHP FATAL): $relPath" -ForegroundColor Red
        Write-Host "      Base Migration property is untyped; 'public bool' fatals. Use: public `$withinTransaction = false;" -ForegroundColor Gray
    }
}
if ($pgMigrationCount -eq 0) { Write-Host "  No PostgreSQL concurrent index transaction issues detected." -ForegroundColor DarkGray }

# 7. Vue 3 Deep Reactivity with Large Lists
Write-Host "`n[7] Scanning for large table reactive ref() in Vue..." -ForegroundColor Yellow
$vueMatches = $frontendFiles | Select-String -Pattern 'const\s+(rows|items|tableData|records|dataList)\s*=\s*ref\(\[\]\)'
$vueCount = 0
foreach ($match in $vueMatches) {
    $vueCount++
    $relPath = $match.Path.Replace((Resolve-Path $TargetDir).Path, '').TrimStart('\/')
    Write-Host "  [i] Potential heavy reactive proxy: $relPath : $($match.LineNumber) (Consider shallowRef for large tables)" -ForegroundColor Yellow
}
if ($vueCount -eq 0) { Write-Host "  No heavy ref([]) patterns detected." -ForegroundColor DarkGray }

Write-Host "`n=== Anti-Pattern Scan Complete ===" -ForegroundColor Cyan
