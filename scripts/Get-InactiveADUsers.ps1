<#
.SYNOPSIS
    Informe de cuentas de usuario de AD sin actividad en los últimos N días.

.DESCRIPTION
    Busca usuarios habilitados cuyo LastLogonTimestamp sea anterior al umbral
    (o que nunca hayan iniciado sesión) y genera un informe en CSV y en HTML.
    Es solo lectura: no modifica ninguna cuenta.

    Nota: LastLogonTimestamp se replica entre DCs con un retraso de hasta ~14 días,
    así que es fiable para detectar inactividad de semanas o meses, no de días.

.PARAMETER DaysInactive
    Días sin inicio de sesión para considerar la cuenta inactiva. Por defecto 90.

.PARAMETER SearchBase
    OU donde buscar. Si se omite, busca en todo el dominio.

.PARAMETER OutputFolder
    Carpeta donde guardar los informes. Por defecto, la carpeta actual.

.EXAMPLE
    .\Get-InactiveADUsers.ps1 -DaysInactive 90

.EXAMPLE
    .\Get-InactiveADUsers.ps1 -DaysInactive 60 -SearchBase "OU=Usuarios,DC=contoso,DC=local"

.NOTES
    Requiere el módulo ActiveDirectory (RSAT). Solo lectura.
#>
[CmdletBinding()]
param(
    [ValidateRange(1, 3650)]
    [int]$DaysInactive = 90,

    [string]$SearchBase,

    [string]$OutputFolder = '.'
)

#Requires -Modules ActiveDirectory

$cutoff = (Get-Date).AddDays(-$DaysInactive)

$adParams = @{
    Filter     = 'Enabled -eq $true'
    Properties = 'LastLogonTimestamp', 'whenCreated', 'Department', 'Title', 'PasswordLastSet', 'Description'
}
if ($SearchBase) { $adParams.SearchBase = $SearchBase }

$inactive = Get-ADUser @adParams | ForEach-Object {
    $lastLogon = if ($_.LastLogonTimestamp) { [DateTime]::FromFileTime($_.LastLogonTimestamp) } else { $null }

    # Inactiva si nunca ha iniciado sesión (y se creó antes del umbral) o si el último login es anterior al umbral
    $isInactive = if ($lastLogon) { $lastLogon -lt $cutoff } else { $_.whenCreated -lt $cutoff }

    if ($isInactive) {
        [pscustomobject]@{
            SamAccountName  = $_.SamAccountName
            Name            = $_.Name
            Department      = $_.Department
            Title           = $_.Title
            LastLogon       = if ($lastLogon) { $lastLogon.ToString('yyyy-MM-dd') } else { 'Nunca' }
            DaysSinceLogon  = if ($lastLogon) { [int]((Get-Date) - $lastLogon).TotalDays } else { $null }
            PasswordLastSet = if ($_.PasswordLastSet) { $_.PasswordLastSet.ToString('yyyy-MM-dd') } else { '' }
            Created         = $_.whenCreated.ToString('yyyy-MM-dd')
            OU              = ($_.DistinguishedName -split ',', 2)[1]
        }
    }
} | Sort-Object { if ($null -eq $_.DaysSinceLogon) { [int]::MaxValue } else { $_.DaysSinceLogon } } -Descending

$stamp    = Get-Date -Format 'yyyyMMdd_HHmm'
$csvPath  = Join-Path $OutputFolder "inactive-users_$stamp.csv"
$htmlPath = Join-Path $OutputFolder "inactive-users_$stamp.html"

$inactive | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8

$style = @'
<style>
 body { font-family: Segoe UI, Arial, sans-serif; margin: 24px; color: #222; }
 h1 { font-size: 20px; } p { color: #555; }
 table { border-collapse: collapse; width: 100%; font-size: 13px; }
 th, td { border: 1px solid #ddd; padding: 6px 8px; text-align: left; }
 th { background: #f3f3f3; } tr:nth-child(even) { background: #fafafa; }
</style>
'@
$pre = "<h1>Cuentas inactivas (+$DaysInactive días)</h1><p>Generado el $(Get-Date -Format 'yyyy-MM-dd HH:mm') · $(@($inactive).Count) cuentas</p>"
$inactive | ConvertTo-Html -Head $style -PreContent $pre -Title 'Cuentas inactivas' | Out-File -FilePath $htmlPath -Encoding UTF8

Write-Host "$(@($inactive).Count) cuentas inactivas (+$DaysInactive días)." -ForegroundColor Yellow
Write-Host "CSV:  $csvPath"
Write-Host "HTML: $htmlPath"
