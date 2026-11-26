# Tools/sync.ps1 - the dev loop
#
# Copies Dyrutilities and Dyrutilities_Probe into the WoW Forever AddOns folder,
# so there is no manual file shuffling between an edit and a /reload.
#
#   .\Tools\sync.ps1              copy once
#   .\Tools\sync.ps1 -Watch       copy, then re-copy whenever a .lua or .toc file changes
#   .\Tools\sync.ps1 -Link        create directory junctions instead of copying
#   .\Tools\sync.ps1 -WowPath "D:\Program Files (x86)\World of Warcraft"
#   .\Tools\sync.ps1 -NoProbe     the addon only
#
# -Link is the better dev loop: the game reads straight out of the repository,
# so a /reload picks up an edit with no copy step. But the game then also sees
# Documents/, Tests/ and Tools/ (it ignores files the TOC does not list), and
# deleting the junction's contents from inside WoW's folder would reach into
# the repo. Never use it for an install you care about.

[CmdletBinding()]
param(
    [string]$WowPath,
    [switch]$Watch,
    [switch]$Link,
    [switch]$NoProbe
)

$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
$AddonName = "Dyrutilities"
$ProbeName = "Dyrutilities_Probe"
$Flavor = "_forever_"

function Find-WowRoot {
    if ($WowPath) {
        if (-not (Test-Path $WowPath)) { throw "No such path: $WowPath" }
        return $WowPath
    }

    $candidates = @(
        "D:\Program Files (x86)\World of Warcraft",
        "C:\Program Files (x86)\World of Warcraft",
        "C:\Games\World of Warcraft",
        "D:\Games\World of Warcraft"
    )
    foreach ($c in $candidates) {
        if (Test-Path (Join-Path $c $Flavor)) { return $c }
    }

    foreach ($drive in (Get-PSDrive -PSProvider FileSystem).Root) {
        $hit = Get-ChildItem -Path $drive -Filter $Flavor -Directory -Recurse -Depth 3 -ErrorAction SilentlyContinue |
               Select-Object -First 1
        if ($hit) { return (Split-Path -Parent $hit.FullName) }
    }

    throw "Could not find a World of Warcraft install with a $Flavor folder. Pass -WowPath."
}

function Get-AddOnsDir([string]$root) {
    $path = Join-Path $root "$Flavor\Interface\AddOns"
    if (-not (Test-Path $path)) {
        # The client creates it on first launch; creating it here is harmless.
        New-Item -ItemType Directory -Path $path -Force | Out-Null
    }
    return $path
}

function Sync-One([string]$sourceDir, [string]$targetDir, [string]$name) {
    $target = Join-Path $targetDir $name

    if ($Link) {
        if (Test-Path $target) {
            $item = Get-Item $target -Force
            if ($item.LinkType) {
                Write-Host "  = $name already linked" -ForegroundColor DarkGray
                return
            }
            throw "$target exists and is a real folder. Remove it yourself first - this script will not delete a real install."
        }
        New-Item -ItemType Junction -Path $target -Target $sourceDir | Out-Null
        Write-Host "  + $name linked" -ForegroundColor Green
        return
    }

    # Copy mode. Only ever replaces a folder named after this addon, so a
    # mistyped path cannot scribble over an unrelated install. SavedVariables
    # live under WTF\, outside the addon folder, and are never touched.
    if (Test-Path $target) {
        $item = Get-Item $target -Force
        if ($item.LinkType) {
            Write-Host "  = $name is a junction; nothing to copy" -ForegroundColor DarkGray
            return
        }
        Remove-Item $target -Recurse -Force
    }
    Copy-Item -Path $sourceDir -Destination $target -Recurse -Force
    Write-Host "  + $name copied" -ForegroundColor Green
}

function Sync-All {
    $root = Find-WowRoot
    $addOns = Get-AddOnsDir $root
    Write-Host "-> $addOns" -ForegroundColor Cyan

    if ($Link) {
        Sync-One $RepoRoot $addOns $AddonName
    } else {
        $stagingDir = Join-Path $env:TEMP "Dyrutilities_stage"
        if (Test-Path $stagingDir) { Remove-Item $stagingDir -Recurse -Force }
        $staged = Join-Path $stagingDir $AddonName
        New-Item -ItemType Directory -Path $staged -Force | Out-Null

        # The addon is the repo minus everything that is not the addon.
        $exclude = @(
            ".git", ".gitignore", ".gitattributes", ".claude",
            "Documents", "Probe", "Tests", "Tools",
            "README.md", "CLAUDE.md",
            "venv", ".venv", "__pycache__"
        )
        Get-ChildItem -Path $RepoRoot -Force | Where-Object { $exclude -notcontains $_.Name } | ForEach-Object {
            Copy-Item -Path $_.FullName -Destination $staged -Recurse -Force
        }
        Sync-One $staged $addOns $AddonName
    }

    if (-not $NoProbe) {
        Sync-One (Join-Path $RepoRoot "Probe\$ProbeName") $addOns $ProbeName
    }

    Write-Host "Done. /reload in game (restart the client after a first install or a .toc change)." -ForegroundColor Green
}

Sync-All

if ($Watch) {
    Write-Host "Watching $RepoRoot for changes. Ctrl+C to stop." -ForegroundColor Yellow
    $watcher = New-Object System.IO.FileSystemWatcher
    $watcher.Path = $RepoRoot
    $watcher.IncludeSubdirectories = $true
    $watcher.Filter = "*.*"
    $watcher.EnableRaisingEvents = $true

    while ($true) {
        $change = $watcher.WaitForChanged([System.IO.WatcherChangeTypes]::All, 1000)
        if (-not $change.TimedOut -and $change.Name -match '\.(lua|toc|xml)$') {
            Start-Sleep -Milliseconds 250   # let the editor finish writing
            Write-Host "changed: $($change.Name)" -ForegroundColor DarkGray
            try { Sync-All } catch { Write-Host $_ -ForegroundColor Red }
        }
    }
}
