if ($PSVersionTable.PSVersion.Major -le 5) {
    Write-Host "Detectado PowerShell antiguo. Reiniciando en PowerShell 7..." -ForegroundColor Yellow
    Start-Process pwsh -ArgumentList "-File `"$PSCommandPath`""
    exit
}

$BaseDir = $PSScriptRoot
$ConfigPath = Join-Path $BaseDir "data.ini"
$BinDir = Join-Path $BaseDir "bin"
$AriaPath = Join-Path $BinDir "aria2c.exe"

if (Test-Path (Join-Path $BaseDir "W10MUI")) {
    $WorkDir = Join-Path $BaseDir "W10MUI"
} else {
    $WorkDir = $BaseDir
}

$DownloadsDir = Join-Path $WorkDir "Updates"

function GetID {
    param ([string]$IniPath)

    if (-not (Test-Path $IniPath)) {
        Write-Error "No se encontro data.ini."
        exit 1
    }

    $version = (Get-Content $IniPath | Where-Object { $_ -match '^Version=' } | Select-Object -First 1) -replace '^Version=', ''
    $arch = (Get-Content $IniPath | Where-Object { $_ -match '^Arch=' } | Select-Object -First 1) -replace '^Arch=', ''
    $rev = (Get-Content $IniPath | Where-Object { $_ -match '^Rev=' } | Select-Object -First 1) -replace '^Rev=', ''

    if (-not $version -or -not $arch) {
        Write-Error "data.ini debe contener Version y Arch."
        exit 1
    }

    if (-not $rev) {
        $rev = "latest"
    }

    $isLatest = $rev -ieq "latest"
    if (-not $isLatest -and $rev -notmatch '^\d+$') {
        Write-Error "Rev debe ser 'latest' o un numero."
        exit 1
    }

    $searchTerms = if ($isLatest) { "$version $arch" } else { "$version $rev $arch" }
    $query = [uri]::EscapeDataString($searchTerms)
    $url = "https://api.uupdump.net/listid.php?search=$query"
    $resp = Invoke-RestMethod -Uri $url

    $items = $resp.response.builds.PSObject.Properties | ForEach-Object { $_.Value }
    $match = $items |
        Where-Object {
            $_.arch -eq $arch -and
            $_.title -match [regex]::Escape($version) -and
            ($isLatest -or $_.title -match [regex]::Escape($rev))
        } |
        Select-Object -First 1

    if (-not $match) {
        Write-Error "No se encontro UpdateID para Version=$version, Rev=$rev y Arch=$arch."
        exit 1
    }

    return $match.uuid
}

function Get-Aria {
    param ([string]$TargetPath)

    $ariaUrl = "https://uupdump.net/misc/aria2c.exe"
    $ariaDir = Split-Path -Parent $TargetPath

    if (-not (Test-Path $ariaDir)) {
        New-Item -ItemType Directory -Path $ariaDir | Out-Null
    }

    Write-Host "Descargando aria2c.exe..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri $ariaUrl -OutFile $TargetPath
}

function Main {
    param (
        [string]$AriaExe,
        [string]$IniPath,
        [string]$TargetDir
    )

    $id = GetID -IniPath $IniPath
    $ApiUrl = "https://uupdump.net/get.php?id=$id&pack=0&edition=updateOnly&aria2=2"

    if (-not (Test-Path $AriaExe)) {
        Get-Aria -TargetPath $AriaExe
    }

    Write-Host "Descargando script aria2 para las actualizaciones..." -ForegroundColor Cyan
    $raw = Invoke-WebRequest -Uri $ApiUrl -UseBasicParsing
    $lines = $raw.Content -split "`r?`n"

    $downloads = @()
    $currentUrl = $null
    $currentOut = $null

    foreach ($line in $lines) {
        $trim = $line.Trim()

        if ($trim.Length -eq 0 -or $trim.StartsWith("#")) {
            if ($currentUrl -and $currentOut) {
                $downloads += [PSCustomObject]@{ Url = $currentUrl; Out = $currentOut }
                $currentUrl = $null
                $currentOut = $null
            }
            continue
        }

        if ($trim -match '^https?://') {
            $currentUrl = $trim
            continue
        }

        if ($trim -match '^out=(.+)$') {
            $currentOut = $matches[1].Trim()
            continue
        }
    }

    if ($currentUrl -and $currentOut) {
        $downloads += [PSCustomObject]@{ Url = $currentUrl; Out = $currentOut }
    }

    if ($downloads.Count -eq 0) {
        Write-Error "No se encontraron descargas en la respuesta."
        exit 1
    }

    Write-Host "Se encontraron $($downloads.Count) archivos. Iniciando descarga..." -ForegroundColor Green

    foreach ($item in $downloads) {
        $itemPath = Join-Path -Path $TargetDir -ChildPath $item.Out
        $itemDir = Split-Path -Parent $itemPath
        
        if (-not (Test-Path $itemDir)) {
            New-Item -ItemType Directory -Path $itemDir | Out-Null
        }

        Write-Host "-> Bajando: $($item.Out)" -ForegroundColor Yellow
        & $AriaExe --no-conf --allow-overwrite=true --auto-file-renaming=false -x 5 -s 5 -d $itemDir -o (Split-Path -Leaf $itemPath) $item.Url
    }

    Write-Host "Descarga completada." -ForegroundColor Cyan
    if (Test-Path $BinDir) {
        Remove-Item -Path $BinDir -Recurse -Force
    }
}

Main -AriaExe $AriaPath -IniPath $ConfigPath -TargetDir $DownloadsDir