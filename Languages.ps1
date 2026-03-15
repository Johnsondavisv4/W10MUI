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

$DirLangs = Join-Path $WorkDir "Langs"
$DirFODs = Join-Path (Join-Path $WorkDir "OnDemand") "x64"

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
        [string]$LangsDir,
        [string]$FodsDir,
        [string]$IniPath
    )

    $id = GetID -IniPath $IniPath
    $ApiUrl = "https://api.uupdump.net/get.php?id=$id"

    if (-not (Test-Path $AriaExe)) {
        Get-Aria -TargetPath $AriaExe
    }

    Write-Host "Conectando a la API de UUP Dump..." -ForegroundColor Cyan
    $json = (Invoke-WebRequest -Uri $ApiUrl).Content | ConvertFrom-Json -AsHashtable

    if ($json.response.error) {
        Write-Error "La API devolvió error: $($json.response.error)"
        exit 1
    }

    $archivos = $json.response.files

    if (!(Test-Path $LangsDir)) { New-Item -ItemType Directory -Path $LangsDir | Out-Null }
    if (!(Test-Path $FodsDir)) { New-Item -ItemType Directory -Path $FodsDir | Out-Null }

    $downloads = @()
    Write-Host "Buscando archivos objetivos en la respuesta..." -ForegroundColor Cyan

    $RegexPack = "(?=.*LanguagePack)(?=.*es-mx).*"
    $RegexFOD  = "(?=.*LanguageFeatures)(?=.*es-mx).*"

    foreach ($nombreArchivo in $archivos.Keys) {
        $archivoData = $archivos[$nombreArchivo]
        $url = $archivoData.url

        if (-not $url) {
            continue
        }

        if ($nombreArchivo -match $RegexPack) {
            $destino = Join-Path $LangsDir $nombreArchivo
            $downloads += [PSCustomObject]@{ Nombre = $nombreArchivo; Url = $url; Destino = $destino }
        } elseif ($nombreArchivo -match $RegexFOD) {
            $destino = Join-Path $FodsDir $nombreArchivo
            $downloads += [PSCustomObject]@{ Nombre = $nombreArchivo; Url = $url; Destino = $destino }
        }
    }

    if ($downloads.Count -eq 0) {
        Write-Error "No se encontraron descargas en la respuesta."
        exit 1
    }

    Write-Host "Se encontraron $($downloads.Count) archivos coincidentes. Iniciando descarga..." -ForegroundColor Green

    foreach ($descarga in $downloads) {
        Write-Host "-> Bajando: $($descarga.Nombre)"
        $targetDir = Split-Path -Parent $descarga.Destino
        & $AriaExe --no-conf --allow-overwrite=true --auto-file-renaming=false -x 5 -s 5 -d $targetDir -o (Split-Path -Leaf $descarga.Destino) $descarga.Url
    }

    Write-Host "¡Clasificación y descarga completadas! Archivos listos en \Langs y \OnDemand" -ForegroundColor Cyan

    if (Test-Path $BinDir) {
        Remove-Item -Path $BinDir -Recurse -Force
    }
}

Main -AriaExe $AriaPath -LangsDir $DirLangs -FodsDir $DirFODs -IniPath $ConfigPath