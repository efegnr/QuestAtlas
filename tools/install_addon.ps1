<#
.SYNOPSIS
    Installs QuestAtlas into the World of Warcraft AddOns folder.

.DESCRIPTION
    1. Finds the World of Warcraft folder (Battle.net database or the default path).
    2. Finds the game flavor folder (_retail_, _forever_, _classic_era_, ...) by the
       product code in its .flavor.info file.
    3. Reads the client version from .build.info (e.g. 12.1.5 -> Interface 120105)
       and adds that number to "## Interface:" in QuestAtlas.toc if it is missing.
    4. Links (default) or copies the add-on to <flavor>\Interface\AddOns\QuestAtlas.
       A link (directory junction) means every later change in this repository
       is in the game after a /reload - nothing has to be copied again.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools\install_addon.ps1
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools\install_addon.ps1 -Flavor forever -Copy
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools\install_addon.ps1 -Uninstall
#>
param(
    [ValidateSet('retail', 'forever', 'classic_era', 'classic')]
    [string]$Flavor = 'retail',
    [string]$WowPath = '',
    [switch]$Copy,
    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot
$AddonSource = Join-Path $RepoRoot 'QuestAtlas'
$TocPath = Join-Path $AddonSource 'QuestAtlas.toc'
$ProductCodes = @{ retail = 'wow'; forever = 'wow_forever'; classic_era = 'wow_classic_era'; classic = 'wow_classic' }
$FolderNames = @{ retail = '_retail_'; forever = '_forever_'; classic_era = '_classic_era_'; classic = '_classic_' }

function Find-WowRoot {
    if ($WowPath) {
        if (-not (Test-Path -LiteralPath (Join-Path $WowPath '.build.info'))) {
            throw "'$WowPath' is not a World of Warcraft folder (no .build.info)."
        }
        return $WowPath
    }
    $candidates = @()
    $productDb = 'C:\ProgramData\Battle.net\Agent\product.db'
    if (Test-Path -LiteralPath $productDb) {
        $text = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($productDb))
        foreach ($match in [regex]::Matches($text, '[A-Za-z]:[\\/][ -~]*?World of Warcraft')) {
            $candidates += ($match.Value -replace '/', '\')
        }
    }
    $candidates += (Join-Path ${env:ProgramFiles(x86)} 'World of Warcraft')
    $candidates += (Join-Path $env:ProgramFiles 'World of Warcraft')
    foreach ($candidate in ($candidates | Select-Object -Unique)) {
        if (Test-Path -LiteralPath (Join-Path $candidate '.build.info')) {
            return $candidate
        }
    }
    throw "World of Warcraft folder not found. Pass it with -WowPath 'D:\Games\World of Warcraft'."
}

function Find-FlavorFolder([string]$root, [string]$product, [string]$defaultName) {
    $folders = Get-ChildItem -LiteralPath $root -Directory | Where-Object { $_.Name -match '^_.+_$' }
    foreach ($folder in $folders) {
        $info = Join-Path $folder.FullName '.flavor.info'
        if ((Test-Path -LiteralPath $info) -and ((Get-Content -LiteralPath $info) -contains $product)) {
            return $folder.FullName
        }
    }
    $default = Join-Path $root $defaultName
    if (Test-Path -LiteralPath $default) {
        return $default
    }
    $names = ($folders | ForEach-Object { $_.Name }) -join ', '
    throw "Flavor '$Flavor' ($product) is not installed in '$root'. Installed: $names"
}

# Returns @{ Version = '12.1.5.70961'; Interface = 120105 } or $null
function Get-ClientVersion([string]$root, [string]$product) {
    $lines = @(Get-Content -LiteralPath (Join-Path $root '.build.info'))
    if ($lines.Count -lt 2) {
        return $null
    }
    $header = @($lines[0].Split('|') | ForEach-Object { ($_ -split '!')[0] })
    $versionIndex = [array]::IndexOf($header, 'Version')
    $productIndex = [array]::IndexOf($header, 'Product')
    if ($versionIndex -lt 0 -or $productIndex -lt 0) {
        return $null
    }
    for ($i = 1; $i -lt $lines.Count; $i++) {
        $columns = $lines[$i].Split('|')
        if ($columns.Count -gt [Math]::Max($versionIndex, $productIndex) -and $columns[$productIndex] -eq $product) {
            $parts = $columns[$versionIndex].Split('.')
            if ($parts.Count -ge 3) {
                return @{
                    Version   = $columns[$versionIndex]
                    Interface = [int]$parts[0] * 10000 + [int]$parts[1] * 100 + [int]$parts[2]
                }
            }
        }
    }
    return $null
}

# Adds $interface to "## Interface: a, b" in the .toc (UTF-8 without BOM). Returns $true if changed.
function Update-TocInterface([string]$tocPath, [int]$interface) {
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    $text = [IO.File]::ReadAllText($tocPath, $utf8)
    $match = [regex]::Match($text, '(?m)^## Interface:[ \t]*([0-9, \t]+?)[ \t]*\r?$')
    if (-not $match.Success) {
        throw "No '## Interface:' line in $tocPath"
    }
    $numbers = @($match.Groups[1].Value -split '\s*,\s*' | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ })
    if ($numbers -contains $interface) {
        return $false
    }
    $numbers += $interface
    $list = (@($numbers | Sort-Object)) -join ', '
    $group = $match.Groups[1]
    $text = $text.Substring(0, $group.Index) + $list + $text.Substring($group.Index + $group.Length)
    [IO.File]::WriteAllText($tocPath, $text, $utf8)
    return $true
}

function Remove-ExistingInstall([string]$target) {
    if (-not (Test-Path -LiteralPath $target)) {
        return
    }
    $item = Get-Item -LiteralPath $target -Force
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
        # rmdir on a junction removes only the link, never the folder it points to.
        cmd /c rmdir "$target"
        if ($LASTEXITCODE -ne 0) { throw "Could not remove the old link $target" }
    } elseif (Test-Path -LiteralPath (Join-Path $target 'QuestAtlas.toc')) {
        Remove-Item -LiteralPath $target -Recurse -Force
    } else {
        throw "'$target' exists but is not a QuestAtlas install. Remove it by hand first."
    }
}

# ---------------------------------------------------------------------------
$root = Find-WowRoot
$product = $ProductCodes[$Flavor]
$flavorDir = Find-FlavorFolder $root $product $FolderNames[$Flavor]
$addonsDir = Join-Path $flavorDir 'Interface\AddOns'
$target = Join-Path $addonsDir 'QuestAtlas'

Write-Host "World of Warcraft : $root"
Write-Host "Flavor folder     : $flavorDir"

if ($Uninstall) {
    Remove-ExistingInstall $target
    Write-Host "QuestAtlas removed from $addonsDir"
    exit 0
}

$client = Get-ClientVersion $root $product
if ($client) {
    $changed = Update-TocInterface $TocPath $client.Interface
    $note = if ($changed) { 'added to QuestAtlas.toc' } else { 'already in QuestAtlas.toc' }
    Write-Host "Client version    : $($client.Version) -> Interface $($client.Interface) ($note)"
} else {
    Write-Host "Client version    : unknown (no '$product' row in .build.info) - enable 'Load out of date AddOns' in game"
}

New-Item -ItemType Directory -Force -Path $addonsDir | Out-Null
Remove-ExistingInstall $target
if ($Copy) {
    Copy-Item -LiteralPath $AddonSource -Destination $target -Recurse
    Write-Host "Copied            : $target"
} else {
    New-Item -ItemType Junction -Path $target -Target $AddonSource | Out-Null
    Write-Host "Linked            : $target -> $AddonSource"
}
if (-not (Test-Path -LiteralPath (Join-Path $target 'QuestAtlas.toc'))) {
    throw "Install check failed: $target\QuestAtlas.toc not found."
}
Write-Host ""
Write-Host "Done. In game: AddOns button on the character screen -> QuestAtlas enabled, then /qa help"
