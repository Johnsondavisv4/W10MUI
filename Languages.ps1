$BaseDir = $PSScriptRoot
$ConfigPath = Join-Path $BaseDir "data.ini"
$Lang = "es-mx"
$BinDir = Join-Path $BaseDir "bin"
$AriaPath = Join-Path $BinDir "aria2c.exe"
$WorkDir = $null
if (Test-Path (Join-Path $BaseDir "W10MUI")) {
    $WorkDir = Join-Path $BaseDir "W10MUI"
} else {
    $WorkDir = $BaseDir
}
$DirLangs = Join-Path $WorkDir "Langs"
$DirFODs = Join-Path $WorkDir "OnDemand"
$Objetivos = @(
    "Microsoft-Windows-Client-LanguagePack-Package-amd64-es-MX.esd",
    "Microsoft-Windows-LanguageFeatures-Basic-es-mx-Package-amd64.cab",
    "Microsoft-Windows-LanguageFeatures-Handwriting-es-mx-Package-amd64.cab",
    "Microsoft-Windows-LanguageFeatures-OCR-es-mx-Package-amd64.cab",
    "Microsoft-Windows-LanguageFeatures-Speech-es-mx-Package-amd64.cab",
    "Microsoft-Windows-LanguageFeatures-TextToSpeech-es-mx-Package-amd64.cab"
)

function GetID {
    param (
        [string]$IniPath
    )

    if (-not (Test-Path $IniPath)) {
        Write-Error "No se encontro data.ini."
        exit 1
    }

    $version = (Get-Content $IniPath | Where-Object { $_ -match '^Version=' } | Select-Object -First 1) -replace '^Version=', ''
    $arch = (Get-Content $IniPath | Where-Object { $_ -match '^Arch=' } | Select-Object -First 1) -replace '^Arch=', ''

    if (-not $version -or -not $arch) {
        Write-Error "data.ini debe contener Version y Arch."
        exit 1
    }

    $query = [uri]::EscapeDataString("$version $arch")
    $url = "https://api.uupdump.net/listid.php?search=$query"
    $resp = Invoke-RestMethod -Uri $url

    $items = $resp.response.builds.PSObject.Properties | ForEach-Object { $_.Value }
    $match = $items |
        Where-Object { $_.arch -eq $arch -and $_.title -match [regex]::Escape($version) } |
        Select-Object -First 1

    if (-not $match) {
        Write-Error "No se encontro UpdateID para Version=$version y Arch=$arch."
        exit 1
    }

    return $match.uuid
}

function Get-Aria {
    param (
        [string]$TargetPath
    )

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
        [string]$Api,
        [string]$AriaExe,
        [string]$LangsDir,
        [string]$FodsDir,
        [string[]]$Targets,
        [string]$IniPath,
        [string]$Language
    )

    $id = GetID -IniPath $IniPath
    $Api = "https://api.uupdump.net/get.php?id=$id&lang=$Language"

    if (-not (Test-Path $AriaExe)) {
        Get-Aria -TargetPath $AriaExe
    }

    Write-Host "Conectando a la API de UUP Dump..." -ForegroundColor Cyan
    $json = Invoke-RestMethod -Uri $Api
    $archivos = $json.response.files.psobject.properties

    if (!(Test-Path $LangsDir)) { New-Item -ItemType Directory -Path $LangsDir | Out-Null }
    if (!(Test-Path $FodsDir)) { New-Item -ItemType Directory -Path $FodsDir | Out-Null }

    $downloads = @()
    Write-Host "Buscando archivos objetivos en la respuesta..." -ForegroundColor Cyan

    foreach ($archivo in $archivos) {
        $rutaVirtual = $archivo.Name
        $url = $archivo.Value.url
        $nombreReal = $rutaVirtual -replace ".*\\", ""

        if ($Targets -contains $nombreReal) {
            $destino = if ($nombreReal -eq "Microsoft-Windows-Client-LanguagePack-Package-amd64-es-MX.esd") {
                Join-Path $LangsDir $nombreReal
            } else {
                Join-Path $FodsDir $nombreReal
            }

            $downloads += [PSCustomObject]@{ Nombre = $nombreReal; Url = $url; Destino = $destino }
        }
    }

    if ($downloads.Count -eq 0) {
        Write-Error "No se encontraron descargas en la respuesta."
        exit 1
    }

    Write-Host "Se encontraron $($downloads.Count) archivos exactos. Iniciando descarga..." -ForegroundColor Green

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

Main -Api "" -AriaExe $AriaPath -LangsDir $DirLangs -FodsDir $DirFODs -Targets $Objetivos -IniPath $ConfigPath -Language $Lang