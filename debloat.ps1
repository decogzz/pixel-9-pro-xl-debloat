# One-shot Pixel 9 Pro XL debloat. Missing packages are skipped.
# Usage: powershell -ExecutionPolicy Bypass -File debloat.ps1 [-Action Debloat|Restore]
param(
    [ValidateSet('Debloat', 'Restore')]
    [string]$Action = 'Debloat'
)

$ErrorActionPreference = 'Continue'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:Adb = $null

function Find-Adb {
    $candidates = New-Object System.Collections.Generic.List[string]
    foreach ($name in @('adb', 'adb.exe')) {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue
        if ($cmd -and $cmd.Source) { $candidates.Add($cmd.Source) }
    }
    $fixed = @(
        (Join-Path $Root 'adb.exe'),
        (Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe'),
        (Join-Path $env:USERPROFILE 'AppData\Local\Android\Sdk\platform-tools\adb.exe'),
        (Join-Path $env:USERPROFILE 'Downloads\platform-tools-latest-windows\platform-tools\adb.exe'),
        (Join-Path $env:USERPROFILE 'Downloads\platform-tools\adb.exe')
    )
    if ($env:ANDROID_HOME) {
        $fixed += (Join-Path $env:ANDROID_HOME 'platform-tools\adb.exe')
    }
    foreach ($path in $fixed) {
        if ($path -and (Test-Path -LiteralPath $path)) { $candidates.Add($path) }
    }
    return $candidates | Select-Object -First 1
}

function Invoke-Adb {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$AdbArgs)
    $lines = & $script:Adb @AdbArgs 2>&1 | ForEach-Object { "$_" }
    $code = $LASTEXITCODE
    if (-not $lines) { $lines = @() }
    $text = (($lines -join "`n") -replace "`r", '').Trim()
    return [pscustomobject]@{ Code = $code; Text = $text }
}

function Read-List {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return @() }
    $items = @()
    foreach ($raw in Get-Content -LiteralPath $Path) {
        $line = $raw
        $hash = $line.IndexOf('#')
        if ($hash -ge 0) { $line = $line.Substring(0, $hash) }
        $line = $line.Trim()
        if ($line) { $items += $line }
    }
    return $items
}

function Test-Package {
    param([string]$Package)
    $result = Invoke-Adb shell pm path $Package
    return $result.Text -match '(?m)^package:'
}

function Get-PackageUid {
    param([string]$Package)
    $result = Invoke-Adb shell pm list packages -U $Package
    foreach ($line in ($result.Text -split "`n")) {
        if ($line -match "^package:$([regex]::Escape($Package)) uid:(\d+)$") {
            return $Matches[1]
        }
    }
    return $null
}

function Apply-Setting {
    param([string]$Op, [string]$Namespace, [string]$Key, [string]$Value)
    if ($Op -eq 'put') {
        $result = Invoke-Adb shell settings put $Namespace $Key $Value
        if ($result.Code -eq 0) {
            Write-Host "set   $Namespace $Key=$Value"
        } else {
            Write-Host "warn  settings put $Namespace $Key failed, continuing"
        }
    } elseif ($Op -eq 'delete') {
        $result = Invoke-Adb shell settings delete $Namespace $Key
        if ($result.Code -eq 0) {
            Write-Host "del   $Namespace $Key"
        } else {
            Write-Host "warn  settings delete $Namespace $Key failed, continuing"
        }
    } else {
        Write-Host "warn  unknown settings op '$Op', continuing"
    }
}

function Disable-Package {
    param([string]$Package)
    if (-not (Test-Package $Package)) {
        Write-Host "skip  $Package (not installed)"
        return
    }
    $result = Invoke-Adb shell pm disable-user --user 0 $Package
    if ($result.Text -match 'disabled-user') {
        Write-Host "off   $Package"
    } else {
        $detail = $result.Text
        if (-not $detail) { $detail = 'disable failed' }
        Write-Host "warn  $Package ($detail), continuing"
    }
}

function Enable-Package {
    param([string]$Package)
    if (-not (Test-Package $Package)) {
        Write-Host "skip  $Package (not installed)"
        return
    }
    $result = Invoke-Adb shell pm enable --user 0 $Package
    if ($result.Text -match 'enabled|new state') {
        Write-Host "on    $Package"
    } else {
        $detail = $result.Text
        if (-not $detail) { $detail = 'enable failed' }
        Write-Host "warn  $Package ($detail), continuing"
    }
}

function Limit-Package {
    param([string]$Package)
    if (-not (Test-Package $Package)) {
        Write-Host "skip  $Package (not installed)"
        return
    }
    $result = Invoke-Adb shell am set-bg-restriction-level --user 0 $Package background_restricted
    if ($result.Code -ne 0) { Write-Host "warn  $Package background restrict failed, continuing" }
    foreach ($op in @('RUN_IN_BACKGROUND', 'RUN_ANY_IN_BACKGROUND', 'POST_NOTIFICATION', 'SCHEDULE_EXACT_ALARM')) {
        $opResult = Invoke-Adb shell cmd appops set $Package $op ignore
        if ($opResult.Code -ne 0) { Write-Host "warn  $Package appops $op failed, continuing" }
    }
    Invoke-Adb shell pm revoke --user 0 $Package android.permission.POST_NOTIFICATIONS | Out-Null
    $uid = Get-PackageUid $Package
    if ($uid) {
        $policy = Invoke-Adb shell cmd netpolicy add restrict-background-blacklist $uid
        if ($policy.Code -ne 0) { Write-Host "warn  $Package netpolicy failed, continuing" }
    } else {
        Write-Host "warn  $Package uid not found, skipped network blacklist"
    }
    Invoke-Adb shell am force-stop $Package | Out-Null
    Write-Host "limit $Package"
}

function Allow-Package {
    param([string]$Package)
    if (-not (Test-Package $Package)) {
        Write-Host "skip  $Package (not installed)"
        return
    }
    $result = Invoke-Adb shell am set-bg-restriction-level --user 0 $Package adaptive_bucket
    if ($result.Code -ne 0) { Write-Host "warn  $Package background restore failed, continuing" }
    foreach ($op in @('RUN_IN_BACKGROUND', 'RUN_ANY_IN_BACKGROUND', 'POST_NOTIFICATION', 'SCHEDULE_EXACT_ALARM')) {
        $opResult = Invoke-Adb shell cmd appops set $Package $op allow
        if ($opResult.Code -ne 0) { Write-Host "warn  $Package appops $op failed, continuing" }
    }
    $grant = Invoke-Adb shell pm grant --user 0 $Package android.permission.POST_NOTIFICATIONS
    if ($grant.Code -ne 0) { Write-Host "warn  $Package notification grant failed, continuing" }
    $uid = Get-PackageUid $Package
    if ($uid) {
        Invoke-Adb shell cmd netpolicy remove restrict-background-blacklist $uid | Out-Null
    }
    Write-Host "allow $Package"
}

function Stop-Package {
    param([string]$Package)
    if (-not (Test-Package $Package)) {
        Write-Host "skip  $Package (not installed)"
        return
    }
    $result = Invoke-Adb shell am force-stop $Package
    if ($result.Code -ne 0 -and $result.Text) {
        Write-Host "warn  $Package force-stop failed, continuing"
    }
    Write-Host "stop  $Package"
}

$script:Adb = Find-Adb
if (-not $script:Adb) {
    Write-Host "adb was not found. Install platform-tools and put adb on PATH, or place adb.exe next to this script."
    exit 1
}

Write-Host "adb    $($script:Adb)"
$state = Invoke-Adb get-state
$stateText = ($state.Text -split "`n" | Select-Object -First 1)
if ($stateText -ne 'device') {
    Write-Host "No authorized Pixel ($stateText)."
    Write-Host "Plug in the phone, unlock it, and allow USB debugging."
    exit 1
}

$model = (Invoke-Adb shell getprop ro.product.model).Text
Write-Host "phone  $model"
Write-Host "action $Action"

if ($Action -eq 'Debloat') {
    $settingsFile = Join-Path $Root 'debloat-settings.txt'
} else {
    $settingsFile = Join-Path $Root 'restore-settings.txt'
}

foreach ($line in @(Read-List $settingsFile)) {
    $parts = $line -split '\s+', 4
    $value = ''
    if ($parts.Length -ge 4) { $value = $parts[3] }
    Apply-Setting $parts[0] $parts[1] $parts[2] $value
}

foreach ($package in @(Read-List (Join-Path $Root 'disable-packages.txt'))) {
    if ($Action -eq 'Debloat') { Disable-Package $package } else { Enable-Package $package }
}

foreach ($package in @(Read-List (Join-Path $Root 'restrict-packages.txt'))) {
    if ($Action -eq 'Debloat') { Limit-Package $package } else { Allow-Package $package }
}

if ($Action -eq 'Debloat') {
    foreach ($package in @(Read-List (Join-Path $Root 'stop-packages.txt'))) {
        Stop-Package $package
    }
    $trim = Invoke-Adb shell pm trim-caches 999999999999
    if ($trim.Code -ne 0) { Write-Host "warn  trim-caches failed, continuing" }
}

Invoke-Adb shell cmd appops write-settings | Out-Null
Write-Host "done   $Action"
exit 0
