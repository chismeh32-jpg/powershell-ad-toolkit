<#
.SYNOPSIS
    Crea usuarios de Active Directory de forma masiva a partir de un CSV.

.DESCRIPTION
    Lee un CSV con los datos de los nuevos empleados y crea cada cuenta en la OU
    indicada, con contraseña inicial aleatoria y cambio obligatorio en el primer
    inicio de sesión. Opcionalmente añade el usuario a los grupos indicados.

    - Admite -WhatIf para simular sin crear nada.
    - Si el SamAccountName ya existe, lo omite (no sobrescribe cuentas).
    - Genera un CSV de resultado con las contraseñas iniciales para entregarlas
      por un canal seguro (gestor de contraseñas) y borrarlo después.

.PARAMETER CsvPath
    Ruta al CSV. Columnas: FirstName, LastName, Department, Title, OU, Groups
    (Groups separado por ';', opcional).

.PARAMETER UpnSuffix
    Sufijo UPN del dominio, por ejemplo "contoso.local".

.PARAMETER OutputPath
    Ruta del CSV de resultados. Por defecto, en la carpeta actual.

.EXAMPLE
    .\New-ADUsersFromCsv.ps1 -CsvPath .\samples\new-users.csv -UpnSuffix contoso.local -WhatIf

.EXAMPLE
    .\New-ADUsersFromCsv.ps1 -CsvPath .\samples\new-users.csv -UpnSuffix contoso.local

.NOTES
    Requiere el módulo ActiveDirectory (RSAT) y permisos para crear usuarios en la OU.
    Probado en laboratorio (contoso.local). No contiene datos de ninguna empresa real.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [string]$CsvPath,

    [Parameter(Mandatory)]
    [string]$UpnSuffix,

    [string]$OutputPath = ".\new-users-result_$(Get-Date -Format 'yyyyMMdd_HHmm').csv"
)

#Requires -Modules ActiveDirectory

function New-RandomPassword {
    param([int]$Length = 16)
    # Garantiza al menos una mayúscula, minúscula, número y símbolo
    $upper   = 'ABCDEFGHJKLMNPQRSTUVWXYZ'.ToCharArray()
    $lower   = 'abcdefghijkmnopqrstuvwxyz'.ToCharArray()
    $digits  = '23456789'.ToCharArray()
    $symbols = '!@#$%*-_+?'.ToCharArray()
    $all     = $upper + $lower + $digits + $symbols

    $chars = @(
        ($upper   | Get-Random)
        ($lower   | Get-Random)
        ($digits  | Get-Random)
        ($symbols | Get-Random)
    )
    $chars += 1..($Length - 4) | ForEach-Object { $all | Get-Random }
    -join ($chars | Sort-Object { Get-Random })
}

function Remove-Diacritics {
    param([string]$Text)
    $normalized = $Text.Normalize([Text.NormalizationForm]::FormD)
    -join ($normalized.ToCharArray() | Where-Object {
        [Globalization.CharUnicodeInfo]::GetUnicodeCategory($_) -ne 'NonSpacingMark'
    })
}

function Get-SamAccountName {
    # Convención: inicial del nombre + primer apellido, minúsculas, sin acentos ni espacios. Máx. 20 caracteres.
    param([string]$FirstName, [string]$LastName)
    $first = (Remove-Diacritics $FirstName).Trim().ToLower()
    $last  = ((Remove-Diacritics $LastName).Trim().ToLower() -split '\s+')[0]
    $sam   = ($first.Substring(0, 1) + $last) -replace '[^a-z0-9]', ''
    if ($sam.Length -gt 20) { $sam = $sam.Substring(0, 20) }
    $sam
}

$users   = Import-Csv -Path $CsvPath -Delimiter ','
$results = [System.Collections.Generic.List[object]]::new()

foreach ($u in $users) {
    $sam         = Get-SamAccountName -FirstName $u.FirstName -LastName $u.LastName
    $upn         = "$sam@$UpnSuffix"
    $displayName = "$($u.FirstName) $($u.LastName)".Trim()

    # No sobrescribir cuentas existentes
    if (Get-ADUser -Filter "SamAccountName -eq '$sam'" -ErrorAction SilentlyContinue) {
        Write-Warning "Ya existe '$sam' ($displayName). Se omite."
        $results.Add([pscustomobject]@{ SamAccountName = $sam; DisplayName = $displayName; Status = 'Omitido (ya existe)'; InitialPassword = '' })
        continue
    }

    if (-not (Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$($u.OU)'" -ErrorAction SilentlyContinue)) {
        Write-Warning "La OU '$($u.OU)' no existe. Se omite '$sam'."
        $results.Add([pscustomobject]@{ SamAccountName = $sam; DisplayName = $displayName; Status = 'Error: OU no existe'; InitialPassword = '' })
        continue
    }

    $password = New-RandomPassword
    $params = @{
        Name                  = $displayName
        GivenName             = $u.FirstName
        Surname               = $u.LastName
        DisplayName           = $displayName
        SamAccountName        = $sam
        UserPrincipalName     = $upn
        Department            = $u.Department
        Title                 = $u.Title
        Path                  = $u.OU
        AccountPassword       = (ConvertTo-SecureString $password -AsPlainText -Force)
        ChangePasswordAtLogon = $true
        Enabled               = $true
    }

    if ($PSCmdlet.ShouldProcess($displayName, "Crear usuario $sam en $($u.OU)")) {
        try {
            New-ADUser @params -ErrorAction Stop

            # Grupos (opcional)
            if ($u.Groups) {
                foreach ($g in ($u.Groups -split ';' | Where-Object { $_.Trim() })) {
                    try   { Add-ADGroupMember -Identity $g.Trim() -Members $sam -ErrorAction Stop }
                    catch { Write-Warning "No se pudo añadir '$sam' al grupo '$g': $($_.Exception.Message)" }
                }
            }

            Write-Host "Creado: $sam ($displayName)" -ForegroundColor Green
            $results.Add([pscustomobject]@{ SamAccountName = $sam; DisplayName = $displayName; Status = 'Creado'; InitialPassword = $password })
        }
        catch {
            Write-Warning "Error creando '$sam': $($_.Exception.Message)"
            $results.Add([pscustomobject]@{ SamAccountName = $sam; DisplayName = $displayName; Status = "Error: $($_.Exception.Message)"; InitialPassword = '' })
        }
    }
    else {
        $results.Add([pscustomobject]@{ SamAccountName = $sam; DisplayName = $displayName; Status = 'Simulado (-WhatIf)'; InitialPassword = '' })
    }
}

$results | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
Write-Host "`nResultado guardado en $OutputPath" -ForegroundColor Cyan
Write-Warning "El fichero de resultados contiene contraseñas iniciales. Entrégalas por un canal seguro y bórralo."
