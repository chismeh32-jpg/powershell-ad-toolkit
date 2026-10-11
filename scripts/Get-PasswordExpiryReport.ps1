<#
.SYNOPSIS
    Lista los usuarios cuya contraseña caduca en los próximos N días.

.DESCRIPTION
    Usa el atributo calculado msDS-UserPasswordExpiryTimeComputed, que tiene en cuenta
    tanto la directiva de dominio como las Fine-Grained Password Policies (PSO).
    Excluye cuentas deshabilitadas y las marcadas con "La contraseña nunca caduca".
    Solo lectura.

.PARAMETER DaysAhead
    Ventana en días. Por defecto 14.

.PARAMETER SearchBase
    OU donde buscar. Si se omite, todo el dominio.

.PARAMETER OutputPath
    Ruta del CSV de salida (opcional). Si se omite, solo muestra la tabla en pantalla.

.EXAMPLE
    .\Get-PasswordExpiryReport.ps1 -DaysAhead 7

.EXAMPLE
    .\Get-PasswordExpiryReport.ps1 -DaysAhead 14 -OutputPath .\password-expiry.csv

.NOTES
    Requiere el módulo ActiveDirectory (RSAT). Solo lectura.
    Idea de ampliación: enviar un aviso por correo a cada usuario (Send-MailMessage está obsoleto;
    usar Microsoft Graph o un relay SMTP interno).
#>
[CmdletBinding()]
param(
    [ValidateRange(1, 365)]
    [int]$DaysAhead = 14,

    [string]$SearchBase,

    [string]$OutputPath
)

#Requires -Modules ActiveDirectory

$now   = Get-Date
$limit = $now.AddDays($DaysAhead)

$adParams = @{
    Filter     = 'Enabled -eq $true -and PasswordNeverExpires -eq $false'
    Properties = 'msDS-UserPasswordExpiryTimeComputed', 'mail', 'PasswordLastSet', 'Department'
}
if ($SearchBase) { $adParams.SearchBase = $SearchBase }

$report = Get-ADUser @adParams | ForEach-Object {
    $raw = $_.'msDS-UserPasswordExpiryTimeComputed'
    # 0 o el valor máximo indican "no caduca" / no aplicable
    if (-not $raw -or $raw -eq 0 -or $raw -eq 9223372036854775807) { return }

    $expires = [DateTime]::FromFileTime($raw)
    if ($expires -le $limit) {
        [pscustomobject]@{
            SamAccountName  = $_.SamAccountName
            Name            = $_.Name
            Mail            = $_.mail
            Department      = $_.Department
            PasswordLastSet = if ($_.PasswordLastSet) { $_.PasswordLastSet.ToString('yyyy-MM-dd') } else { '' }
            Expires         = $expires.ToString('yyyy-MM-dd HH:mm')
            DaysLeft        = [math]::Floor(($expires - $now).TotalDays)
            Status          = if ($expires -lt $now) { 'Caducada' } else { 'Por caducar' }
        }
    }
} | Sort-Object DaysLeft

$report | Format-Table -AutoSize

if ($OutputPath) {
    $report | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
    Write-Host "Guardado en $OutputPath" -ForegroundColor Cyan
}

Write-Host "$(@($report).Count) usuarios con la contraseña caducada o por caducar en $DaysAhead días." -ForegroundColor Yellow
