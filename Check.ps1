if ($PSVersionTable.PSVersion.Major -le 5) {
    Write-Host "Detectado PowerShell antiguo. Reiniciando en PowerShell 7..." -ForegroundColor Yellow
    Start-Process pwsh -ArgumentList "-File `"$PSCommandPath`""
    exit
}

$BaseDir = $PSScriptRoot
$ConfigPath = Join-Path $BaseDir "data.ini"

function Get-Data {
    param ([string]$IniPath)

    if (-not (Test-Path $IniPath)) {
        Write-Error "No se encontro data.ini."
        exit 1
    }

    $version = (Get-Content $IniPath | Where-Object { $_ -match '^Version=' } | Select-Object -First 1) -replace '^Version=', ''
    $arch = (Get-Content $IniPath | Where-Object { $_ -match '^Arch=' } | Select-Object -First 1) -replace '^Arch=', ''
    $rev = (Get-Content $IniPath | Where-Object { $_ -match '^Rev=' } | Select-Object -First 1) -replace '^Rev=', ''
    $lang = (Get-Content $IniPath | Where-Object { $_ -match '^Lang=' } | Select-Object -First 1) -replace '^Lang=', ''

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

    return @{ version = $version; arch = $arch; rev = $rev; lang = $lang; isLatest = $isLatest }
}

function Get-BuildInfo {
    param (
        [string]$version,
        [string]$arch,
        [string]$rev,
        [bool]$isLatest
    )

    $searchTerms1 = if ($isLatest) { "Windows 11, version $version $arch" } else { "Windows 11, version $version $rev $arch" }
    $query1 = [uri]::EscapeDataString($searchTerms1)
    $url1 = "https://api.uupdump.net/listid.php?search=$query1"
    
    $resp1 = Invoke-RestMethod -Uri $url1

    if ($resp1.response.builds) {
        $items1 = $resp1.response.builds.PSObject.Properties | ForEach-Object { $_.Value }
        
        $match = $items1 |
            Where-Object {
                $_.arch -eq $arch -and
                $_.title -match [regex]::Escape($version) -and
                ($isLatest -or $_.title -match [regex]::Escape($rev))
            } |
            Select-Object -First 1

        if ($match) {
            return @{
                MatchFound   = $true
                SearchMethod = "Primera búsqueda ($version)"
                Title        = $match.title
                Build        = $match.build
                Arch         = $match.arch
                UUID         = $match.uuid
            }
        }
    }
    
    if ($resp1.response.error -eq "SEARCH_NO_RESULTS" -or -not $match) {
        $buildBase = ""
        switch ($version) {
            "25H2" { $buildBase = "26200" }
            "24H2" { $buildBase = "26100" }
            "23H2" { $buildBase = "22631" }
            "22H2" { $buildBase = "22621" }
            "21H2" { $buildBase = "22000" }
        }

        if ($buildBase) {
            Write-Host "-> Primera búsqueda sin coincidencias. Intentando segunda búsqueda..." -ForegroundColor Yellow
            
            $searchTerms2 = if ($isLatest) { "Update for Windows 11 $buildBase $arch" } else { "Update for Windows 11 $buildBase $rev $arch" }
            $query2 = [uri]::EscapeDataString($searchTerms2)
            $url2 = "https://api.uupdump.net/listid.php?search=$query2"
            
            $resp2 = Invoke-RestMethod -Uri $url2
            
            if ($resp2.response.builds) {
                $items2 = $resp2.response.builds.PSObject.Properties | ForEach-Object { $_.Value }
                
                $match = $items2 |
                    Where-Object {
                        $_.arch -eq $arch -and
                        $_.title -match "Update for Windows 11" -and
                        $_.title -match [regex]::Escape($buildBase) -and
                        ($isLatest -or $_.title -match [regex]::Escape($rev))
                    } |
                    Select-Object -First 1
                    
                if ($match) {
                    return @{
                        MatchFound   = $true
                        SearchMethod = "Segunda búsqueda (Update for Windows 11 - $buildBase)"
                        Title        = $match.title
                        Build        = $match.build
                        Arch         = $match.arch
                        UUID         = $match.uuid
                    }
                }
            }
        }
    }

    Write-Error "No se encontro información de compilación para Version=$version, Rev=$rev y Arch=$arch en ninguna de las búsquedas."
    exit 1
}

function Main {
    param (
        [string]$IniPath
    )

    Write-Host "Cargando configuración desde data.ini..." -ForegroundColor Cyan
    $data = Get-Data -IniPath $IniPath
    Write-Host "Buscando en UUP Dump (Version=$($data.version), Arch=$($data.arch), Rev=$($data.rev))..." -ForegroundColor Cyan

    $info = Get-BuildInfo -version $data.version -arch $data.arch -rev $data.rev -isLatest $data.isLatest

    Write-Host "`n========================================" -ForegroundColor Green
    Write-Host "RESULTADO DE LA BÚSQUEDA EN UUP DUMP" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "Método de búsqueda: $($info.SearchMethod)" -ForegroundColor Yellow
    Write-Host "Nombre / Título   : $($info.Title)" -ForegroundColor Cyan
    Write-Host "Compilación       : $($info.Build)" -ForegroundColor Cyan
    Write-Host "Arquitectura      : $($info.Arch)" -ForegroundColor Cyan
    Write-Host "Update ID (UUID)  : $($info.UUID)" -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Green
    
    Write-Host "Presione Enter para salir..." -ForegroundColor Yellow
    Read-Host | Out-Null
}

Main -IniPath $ConfigPath

