# PowerShell AD Toolkit

Scripts de PowerShell para tareas habituales de administración de **Active Directory**: altas masivas, bajas seguras e informes de cuentas inactivas y de contraseñas que van a caducar.

Pensados para el día a día de un equipo de sistemas pequeño: seguros por defecto (`-WhatIf`, sin borrados), con informes en CSV/HTML y comentados en español.

> Todos los ejemplos usan un dominio de laboratorio (`contoso.local`). El repositorio no contiene datos de ninguna empresa real.

> **Estado:** pendiente de validar en un laboratorio propio (Windows Server de evaluación). Revisa y prueba siempre con `-WhatIf` antes de usarlo en producción.

> Desarrollado con asistencia de IA.

## Scripts

| Script | Qué hace | ¿Modifica AD? |
|---|---|---|
| [`New-ADUsersFromCsv.ps1`](scripts/New-ADUsersFromCsv.ps1) | Alta masiva de usuarios desde un CSV: genera el login, una contraseña aleatoria (con cambio obligatorio en el primer inicio de sesión) y los añade a sus grupos. | Sí (admite `-WhatIf`) |
| [`Invoke-ADUserOffboarding.ps1`](scripts/Invoke-ADUserOffboarding.ps1) | Baja de un empleado: guarda sus grupos, deshabilita la cuenta, cambia la contraseña, la quita de los grupos y la mueve a la OU de bajas. **No borra la cuenta.** | Sí (admite `-WhatIf` y pide confirmación) |
| [`Get-InactiveADUsers.ps1`](scripts/Get-InactiveADUsers.ps1) | Informe de cuentas habilitadas sin iniciar sesión en N días, en CSV y HTML. | No |
| [`Get-PasswordExpiryReport.ps1`](scripts/Get-PasswordExpiryReport.ps1) | Usuarios con la contraseña caducada o a punto de caducar (tiene en cuenta las Fine-Grained Password Policies). | No |

## Requisitos

- Windows PowerShell 5.1 o PowerShell 7+
- Módulo `ActiveDirectory` (RSAT): `Add-WindowsCapability -Online -Name Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0`
- Permisos delegados sobre las OUs donde se trabaje

## Uso rápido

```powershell
# Simular un alta masiva (no crea nada)
.\scripts\New-ADUsersFromCsv.ps1 -CsvPath .\samples\new-users.csv -UpnSuffix contoso.local -WhatIf

# Informe de cuentas sin actividad en 90 días
.\scripts\Get-InactiveADUsers.ps1 -DaysInactive 90

# Contraseñas que caducan en la próxima semana
.\scripts\Get-PasswordExpiryReport.ps1 -DaysAhead 7

# Baja de un empleado (primero en modo simulación)
.\scripts\Invoke-ADUserOffboarding.ps1 -Identity lmartinez -DisabledOU "OU=Bajas,DC=contoso,DC=local" -WhatIf
```

Si la directiva de ejecución bloquea los scripts descargados: `Unblock-File .\scripts\*.ps1`.

## Decisiones de diseño

- **`-WhatIf` en todo lo que modifica AD.** Antes de tocar producción, se simula.
- **Las bajas no borran la cuenta.** Eliminar un usuario y volver a crearlo genera un SID nuevo y rompe todo lo que dependía del anterior: permisos NTFS, perfiles FSLogix, buzones… La cuenta se deshabilita y se aparca en una OU de bajas.
- **Copia de los grupos antes de quitarlos**, para poder deshacer la baja con una línea.
- **Las altas no sobrescriben.** Si el login ya existe, se omite y queda registrado en el informe.
- **Entornos híbridos (Entra ID Connect):** AD es la fuente de verdad. Después de cambios, lanza `Start-ADSyncSyncCycle -PolicyType Delta` en el servidor de sincronización.

## Formato del CSV de altas

```csv
FirstName,LastName,Department,Title,OU,Groups
Laura,Martínez Soler,Comercial,Comercial,"OU=Comercial,OU=Usuarios,DC=contoso,DC=local",GG_Comercial;GG_VPN
```

`Groups` es opcional; si hay varios grupos, se separan con `;`. El login se genera como inicial del nombre + primer apellido, sin acentos (`Laura Martínez Soler` → `lmartinez`).

## Próximos pasos

- [ ] Avisos de caducidad de contraseña por correo (Microsoft Graph)
- [ ] Informe de miembros de grupos privilegiados (Domain Admins, etc.)
- [ ] Tests con Pester

## Licencia

MIT
