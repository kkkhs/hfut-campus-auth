param(
    [string]$TaskName = 'CampusAuthAtLogon',
    [string]$CredentialTarget = 'CampusPortalAuth',
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$RuntimeDir = 'C:\ProgramData\CampusAuth'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$sourceScript = Join-Path $RepoRoot 'scripts\campus-auth.ps1'
$configSource = Join-Path $RepoRoot 'config\config.local.json'
$runtimeScript = Join-Path $RuntimeDir 'campus-auth.ps1'
$runtimeConfig = Join-Path $RuntimeDir 'config.json'

if (-not (Test-Path -LiteralPath $sourceScript)) {
    throw "Source script not found: $sourceScript"
}

if (-not (Test-Path -LiteralPath $configSource)) {
    throw "Missing config file: $configSource. Create it from config\\config.example.json first."
}

New-Item -ItemType Directory -Path $RuntimeDir -Force | Out-Null
Copy-Item -LiteralPath $sourceScript -Destination $runtimeScript -Force
Copy-Item -LiteralPath $configSource -Destination $runtimeConfig -Force

$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$runtimeScript`" -CredentialTarget `"$CredentialTarget`""
$trigger = New-ScheduledTaskTrigger -AtLogOn
$trigger.Delay = 'PT30S'
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Description 'HFUT campus portal auth at logon (30s delay).' -Force | Out-Null

Write-Output "Installed scheduled task '$TaskName'."
Write-Output "Runtime script: $runtimeScript"
Write-Output "Runtime config: $runtimeConfig"
Write-Output "Credential target: $CredentialTarget"
