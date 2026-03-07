# Troubleshooting

## 1) Task installed but no internet after login

- Check runtime log:

```powershell
Get-Content C:\ProgramData\CampusAuth\auth.log -Tail 100
```

- Confirm task exists:

```powershell
Get-ScheduledTask -TaskName CampusAuthAtLogon
```

- Verify task action path:

```powershell
(Get-ScheduledTask -TaskName CampusAuthAtLogon).Actions
```

## 2) Credential read failed

- Recreate credential target:

```powershell
cmdkey /delete:CampusPortalAuth
cmdkey /generic:CampusPortalAuth /user:YOUR_STUDENT_ID /pass:YOUR_PASSWORD
```

## 3) Request returns HTTP 200 but login still fails

- Portal request fields may have changed.
- Re-capture the login request via browser DevTools and update `config/config.local.json`.
- Confirm `success_match.contains_any` matches actual response text.

## 4) Script skips auth unexpectedly

- `interface_mode` is set to `ethernet_only`.
- Check if your wired adapter is up:

```powershell
Get-NetAdapter | Format-Table -Auto Name, Status, HardwareInterface, InterfaceDescription
```

## 5) Need manual immediate run

```powershell
powershell -ExecutionPolicy Bypass -File C:\ProgramData\CampusAuth\campus-auth.ps1
```

## 6) Clean reinstall

```powershell
.\scripts\uninstall-task.ps1 -RemoveRuntime
.\scripts\install-task.ps1
```
