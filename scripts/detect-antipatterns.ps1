# Performance Anti-Pattern Scanner for Laravel & Vue 3 (PowerShell)
param (
    [string]$TargetDir = "."
)

Write-Host "=== Scanning for Performance Anti-Patterns in: $TargetDir ===" -ForegroundColor Cyan

# 1. Database Queries Inside Loops
Write-Host "`n[1] Scanning for queries inside loops (Foreach/While)..." -ForegroundColor Yellow
$loopMatches = Get-ChildItem -Path $TargetDir -Recurse -Include *.php -Exclude *Test.php,*.blade.php | Select-String -Pattern '(foreach|while)\s*\(.*?\)\s*\{' -Context 0, 5
foreach ($match in $loopMatches) {
    if ($match.Context.PostContext -match '::(find|where|create|first|update)\(') {
        Write-Host "Potential N+1 or Loop Query: $($match.Filename):$($match.LineNumber)" -ForegroundColor Red
        Write-Host "  $($match.Line.Trim())" -ForegroundColor Gray
    }
}

# 2. Dangerous chunk() usage with updates
Write-Host "`n[2] Scanning for chunk() with updates (should be chunkById)..." -ForegroundColor Yellow
$chunkMatches = Get-ChildItem -Path $TargetDir -Recurse -Include *.php | Select-String -Pattern '->chunk\(' -Context 0, 10
foreach ($match in $chunkMatches) {
    if ($match.Context.PostContext -match '->(update|save|delete)\(') {
        Write-Host "Dangerous chunk() update: $($match.Filename):$($match.LineNumber) (Use chunkById instead)" -ForegroundColor Red
    }
}

# 3. Model $appends with potential N+1
Write-Host "`n[3] Scanning for Model `$appends attributes..." -ForegroundColor Yellow
$appendsMatches = Get-ChildItem -Path "$TargetDir/app/Models" -Recurse -Include *.php -ErrorAction SilentlyContinue | Select-String -Pattern 'protected\s+\$appends\s*='
foreach ($match in $appendsMatches) {
    Write-Host "Model with `$appends: $($match.Filename):$($match.LineNumber)" -ForegroundColor Magenta
    Write-Host "  Verify accessors do not query relationships!" -ForegroundColor DarkGray
}

# 4. Unbounded SELECT * or all()
Write-Host "`n[4] Scanning for unbounded Model::all() calls..." -ForegroundColor Yellow
$allMatches = Get-ChildItem -Path "$TargetDir/app" -Recurse -Include *.php | Select-String -Pattern '[A-Z]\w+::all\(\)'
foreach ($match in $allMatches) {
    Write-Host "Unbounded all(): $($match.Filename):$($match.LineNumber)" -ForegroundColor Red
}

# 5. Vue 3 Deep Reactivity with Large Lists
Write-Host "`n[5] Scanning for large table reactive ref() in Vue..." -ForegroundColor Yellow
$vueMatches = Get-ChildItem -Path "$TargetDir/resources/js" -Recurse -Include *.vue,*.ts,*.js -ErrorAction SilentlyContinue | Select-String -Pattern 'const\s+(rows|items|tableData|records)\s*=\s*ref\(\[\]\)'
foreach ($match in $vueMatches) {
    Write-Host "Potential heavy proxy: $($match.Filename):$($match.LineNumber) (Consider shallowRef)" -ForegroundColor Yellow
}

Write-Host "`n=== Scan Complete ===" -ForegroundColor Cyan
