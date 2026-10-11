<#
.SYNOPSIS
    Baja de un empleado en Active Directory de forma segura y reversible.

.DESCRIPTION
    Pasos que realiza (todos con soporte de -WhatIf):
      1. Exporta a CSV los grupos del usuario (para poder restaurarlos).
      2. Deshabilita la cuenta.
      3. Restablece la contraseña a un valor aleatorio.
      4. Quita al usuario de todos sus grupos (excepto el grupo primario).
      5. Anota la fecha de baja en la descripción.
      6. Mueve la cuenta a la OU de bajas.

    La cuenta NO se elimina. Borrar y recrear un usuario genera un SID nuevo y rompe todo
    lo que depende del original (permisos NTFS, perfiles FSLogix, buzones...). Por eso se
    deshabilita y se aparca en una OU de bajas; el borrado, si procede, se hace más tarde.

.PARAMETER Identity
    SamAccountName del usuario.

.PARAMETER DisabledOU
    DistinguishedName de la OU de bajas, por ejemplo "OU=Bajas,DC=contoso,DC=local".

.PARAMETER BackupFolder
    Carpeta donde guardar la copia de los grupos. Por defecto, la carpeta actual.

.EXAMPLE
    .\Invoke-ADUserOffboarding.ps1 -Identity jgarcia -DisabledOU "OU=Bajas,DC=contoso,DC=local" -WhatIf

.EXAMPLE
    .\Invoke-ADUserOffboarding.ps1 -Identity jgarcia -DisabledOU "OU=Bajas,DC=contoso,DC=local" -Confirm

.NOTES
    Requiere el módulo ActiveDirectory (RSAT).
    En entornos híbridos, lanzar después un ciclo de sincronización: Start-ADSyncSyncCycle -PolicyType Delta
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)]
    [string]$Identity,

    [Parameter(Mandatory)]
    [string]$DisabledOU,

    [string]$BackupFolder = '.'
)

#Requires -Modules ActiveDirectory

$ErrorActionPreference = 'Stop'

$user = Get-ADUser -Identity $Identity -Properties MemberOf, Description, PrimaryGroup
if (-not (Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$DisabledOU'")) {
    throw "La OU de bajas '$DisabledOU' no existe."
}

$target = "$($user.Name) ($($user.SamAccountName))"

# 1. Copia de los grupos
$backupPath = Join-Path $BackupFolder "offboarding_$($user.SamAccountName)_$(Get-Date -Format 'yyyyMMdd_HHmm').csv"
$groups = $user.MemberOf | ForEach-Object { Get-ADGroup -Identity $_ } |
    Where-Object { $_.DistinguishedName -ne $user.PrimaryGroup }

$groups | Select-Object Name, DistinguishedName | Export-Csv -Path $backupPath -NoTypeInformation -Encoding UTF8
Write-Host "Grupos guardados en $backupPath ($(@($groups).Count) grupos)" -ForegroundColor Cyan

# 2. Deshabilitar
if ($PSCmdlet.ShouldProcess($target, 'Deshabilitar cuenta')) {
    Disable-ADAccount -Identity $user
}

# 3. Contraseña aleatoria (corta cualquier sesión que dependa de la contraseña antigua)
if ($PSCmdlet.ShouldProcess($target, 'Restablecer contraseña a un valor aleatorio')) {
    $bytes = New-Object byte[] 24
    [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    $random = [Convert]::ToBase64String($bytes) + 'aA1!'
    Set-ADAccountPassword -Identity $user -Reset -NewPassword (ConvertTo-SecureString $random -AsPlainText -Force)
}

# 4. Quitar de los grupos
foreach ($g in $groups) {
    if ($PSCmdlet.ShouldProcess($target, "Quitar del grupo '$($g.Name)'")) {
        Remove-ADGroupMember -Identity $g -Members $user -Confirm:$false
    }
}

# 5. Anotar la baja
$note = "BAJA $(Get-Date -Format 'yyyy-MM-dd') | $($user.Description)".TrimEnd(' |')
if ($PSCmdlet.ShouldProcess($target, "Actualizar descripción: '$note'")) {
    Set-ADUser -Identity $user -Description $note
}

# 6. Mover a la OU de bajas
if ($PSCmdlet.ShouldProcess($target, "Mover a $DisabledOU")) {
    Move-ADObject -Identity $user.DistinguishedName -TargetPath $DisabledOU
}

Write-Host "Baja completada para $target." -ForegroundColor Green
Write-Host "Para restaurar los grupos: Import-Csv '$backupPath' | ForEach-Object { Add-ADGroupMember -Identity `$_.DistinguishedName -Members '$($user.SamAccountName)' }"
