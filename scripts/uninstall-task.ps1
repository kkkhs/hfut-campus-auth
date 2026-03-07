param(
    [string]$TaskName = 'CampusAuthAtLogon',
    [switch]$RemoveRuntime,
    [string]$RuntimeDir = 'C:\ProgramData\CampusAuth'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($existing) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    Write-Output "Removed scheduled task '$TaskName'."
}
else {
    Write-Output "Scheduled task '$TaskName' does not exist."
}

if ($RemoveRuntime -and (Test-Path -LiteralPath $RuntimeDir)) {
    Remove-Item -LiteralPath $RuntimeDir -Recurse -Force
    Write-Output "Removed runtime directory: $RuntimeDir"
}
