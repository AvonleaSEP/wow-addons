# Installs or updates Spliff's WoW Forever addons from the latest GitHub release.
# Run it with Update-SpliffAddons.bat (double-click). Safe to run any time;
# if WoW is open, type /reload in game afterwards (new addons need a restart).

$ErrorActionPreference = 'Stop'
$Repo = 'AvonleaSEP/wow-addons'
$Asset = 'SpliffAddons.zip'
$SavedPath = Join-Path $PSScriptRoot 'addons-path.txt'

function Find-AddOnsFolder {
    # 1. the folder picked last time
    if (Test-Path $SavedPath) {
        $p = (Get-Content $SavedPath -Raw).Trim()
        if ($p -and (Test-Path $p)) { return $p }
    }
    # 2. the usual places, on every drive
    $tails = @(
        'Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns',
        'Program Files\World of Warcraft\_forever_\Interface\AddOns',
        'World of Warcraft\_forever_\Interface\AddOns',
        'Games\World of Warcraft\_forever_\Interface\AddOns',
        'Battle.net\World of Warcraft\_forever_\Interface\AddOns',
        'BattleNet\World of Warcraft\_forever_\Interface\AddOns'
    )
    foreach ($drive in (Get-PSDrive -PSProvider FileSystem)) {
        foreach ($tail in $tails) {
            $p = Join-Path $drive.Root $tail
            if (Test-Path $p) { return $p }
        }
    }
    # 3. ask
    Add-Type -AssemblyName System.Windows.Forms
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = 'Pick your WoW Forever folder (the one called _forever_)'
    if ($dlg.ShowDialog() -ne 'OK') { throw 'No folder picked.' }
    $p = $dlg.SelectedPath
    if ((Split-Path $p -Leaf) -ne 'AddOns') { $p = Join-Path $p 'Interface\AddOns' }
    New-Item -ItemType Directory -Force $p | Out-Null
    return $p
}

Write-Host "Spliff's addons: checking for the latest version..." -ForegroundColor Yellow
$addOns = Find-AddOnsFolder
Set-Content -Path $SavedPath -Value $addOns
Write-Host "AddOns folder: $addOns"

$release = Invoke-RestMethod "https://api.github.com/repos/$Repo/releases/latest" -Headers @{ 'User-Agent' = 'SpliffAddons-Updater' }
$file = $release.assets | Where-Object { $_.name -eq $Asset } | Select-Object -First 1
if (-not $file) { throw "The latest release ($($release.tag_name)) has no $Asset." }

$tmp = Join-Path $env:TEMP ('SpliffAddons-' + [guid]::NewGuid())
New-Item -ItemType Directory $tmp | Out-Null
try {
    $zip = Join-Path $tmp $Asset
    Invoke-WebRequest $file.browser_download_url -OutFile $zip -Headers @{ 'User-Agent' = 'SpliffAddons-Updater' }
    $unpacked = Join-Path $tmp 'unpacked'
    Expand-Archive $zip -DestinationPath $unpacked

    foreach ($dir in Get-ChildItem $unpacked -Directory) {
        $dest = Join-Path $addOns $dir.Name
        if (Test-Path $dest) {
            $existing = Get-Item $dest -Force
            if ($existing.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                # a developer's linked folder: never touch it
                Write-Host "  $($dir.Name): linked to a source folder here, left alone" -ForegroundColor DarkGray
                continue
            }
            Remove-Item $dest -Recurse -Force
        }
        Copy-Item $dir.FullName $dest -Recurse
        Write-Host "  $($dir.Name)" -ForegroundColor Green
    }
}
finally {
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "Done: version $($release.tag_name) installed." -ForegroundColor Yellow
if (Get-Process -Name 'Wow' -ErrorAction SilentlyContinue) {
    Write-Host "WoW is open: type /reload in game (or restart WoW if an addon is new)." -ForegroundColor Cyan
}
