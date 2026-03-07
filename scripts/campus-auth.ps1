param(
    [string]$ConfigPath = 'C:\ProgramData\CampusAuth\config.json',
    [string]$CredentialTarget = 'CampusPortalAuth',
    [string]$LogPath = 'C:\ProgramData\CampusAuth\auth.log'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-StructuredLog {
    param(
        [string]$Level,
        [string]$Message,
        [hashtable]$Data
    )

    $logDir = Split-Path -Parent $LogPath
    if (-not (Test-Path -LiteralPath $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }

    $entry = @{
        timestamp = (Get-Date).ToString('o')
        level     = $Level
        message   = $Message
    }

    if ($Data) {
        foreach ($key in $Data.Keys) {
            $entry[$key] = $Data[$key]
        }
    }

    ($entry | ConvertTo-Json -Compress -Depth 10) | Add-Content -LiteralPath $LogPath -Encoding UTF8
}

function ConvertTo-NativeObject {
    param([object]$InputObject)

    if ($null -eq $InputObject) { return $null }

    if ($InputObject -is [System.Management.Automation.PSCustomObject]) {
        $hash = @{}
        foreach ($prop in $InputObject.PSObject.Properties) {
            $hash[$prop.Name] = ConvertTo-NativeObject -InputObject $prop.Value
        }
        return $hash
    }

    if ($InputObject -is [System.Collections.IEnumerable] -and -not ($InputObject -is [string])) {
        $items = @()
        foreach ($item in $InputObject) {
            $items += ,(ConvertTo-NativeObject -InputObject $item)
        }
        return $items
    }

    return $InputObject
}

function Resolve-Template {
    param(
        [object]$Value,
        [hashtable]$Map
    )

    if ($null -eq $Value) { return $null }

    if ($Value -is [string]) {
        $resolved = $Value
        foreach ($key in $Map.Keys) {
            $resolved = $resolved.Replace("{{$key}}", [string]$Map[$key])
        }
        return $resolved
    }

    if ($Value -is [System.Collections.IDictionary]) {
        $resolvedHash = @{}
        foreach ($key in $Value.Keys) {
            $resolvedHash[$key] = Resolve-Template -Value $Value[$key] -Map $Map
        }
        return $resolvedHash
    }

    if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])) {
        $resolvedItems = @()
        foreach ($item in $Value) {
            $resolvedItems += ,(Resolve-Template -Value $item -Map $Map)
        }
        return $resolvedItems
    }

    return $Value
}

function Test-EthernetConnected {
    $wifiPattern = 'Wi-?Fi|Wireless|WLAN|无线'
    $adapters = Get-NetAdapter -ErrorAction Stop | Where-Object { $_.Status -eq 'Up' -and $_.HardwareInterface }
    if (-not $adapters) { return $false }

    $ethernet = $adapters | Where-Object {
        ($_.Name -match 'Ethernet|以太网') -or
        ($_.InterfaceDescription -match 'Ethernet|以太网') -or
        (($_.Name -notmatch $wifiPattern) -and ($_.InterfaceDescription -notmatch $wifiPattern))
    }

    return [bool]$ethernet
}

function Get-GenericCredential {
    param([string]$Target)

    if (-not ('Win32Credential' -as [type])) {
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Text;

public static class Win32Credential
{
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct CREDENTIAL
    {
        public int Flags;
        public int Type;
        public IntPtr TargetName;
        public IntPtr Comment;
        public long LastWritten;
        public int CredentialBlobSize;
        public IntPtr CredentialBlob;
        public int Persist;
        public int AttributeCount;
        public IntPtr Attributes;
        public IntPtr TargetAlias;
        public IntPtr UserName;
    }

    [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern bool CredRead(string target, int type, int reservedFlag, out IntPtr credentialPtr);

    [DllImport("advapi32.dll", SetLastError = true)]
    public static extern void CredFree(IntPtr credentialPtr);

    public static string GetBlobAsString(IntPtr blobPtr, int blobSize)
    {
        if (blobPtr == IntPtr.Zero || blobSize <= 0) { return string.Empty; }
        byte[] blob = new byte[blobSize];
        Marshal.Copy(blobPtr, blob, 0, blobSize);
        return Encoding.Unicode.GetString(blob).TrimEnd('\0');
    }
}
"@
    }

    $credentialPtr = [IntPtr]::Zero
    $ok = [Win32Credential]::CredRead($Target, 1, 0, [ref]$credentialPtr)
    if (-not $ok) {
        $code = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        throw "Failed to read credential target '$Target'. Win32Error=$code"
    }

    try {
        $cred = [Runtime.InteropServices.Marshal]::PtrToStructure($credentialPtr, [type][Win32Credential+CREDENTIAL])
        $username = [Runtime.InteropServices.Marshal]::PtrToStringUni($cred.UserName)
        $password = [Win32Credential]::GetBlobAsString($cred.CredentialBlob, $cred.CredentialBlobSize)
        if ([string]::IsNullOrWhiteSpace($username) -or [string]::IsNullOrWhiteSpace($password)) {
            throw "Credential target '$Target' exists but username/password is empty."
        }
        return @{ username = $username; password = $password }
    }
    finally {
        if ($credentialPtr -ne [IntPtr]::Zero) { [Win32Credential]::CredFree($credentialPtr) }
    }
}

function Get-Md5Hex {
    param([string]$InputText)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($InputText)
    $md5 = [System.Security.Cryptography.MD5]::Create()
    try {
        $hash = $md5.ComputeHash($bytes)
        return ([System.BitConverter]::ToString($hash)).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $md5.Dispose()
    }
}

function Get-DrcomPageContext {
    param([string]$PortalPageUrl)

    $resp = Invoke-WebRequest -Uri $PortalPageUrl -TimeoutSec 15 -UseBasicParsing
    $html = [string]$resp.Content

    $jsRelative = $null
    $jsMatch = [regex]::Match($html, 'src="([^"]+\.js)"', 'IgnoreCase')
    if ($jsMatch.Success) { $jsRelative = $jsMatch.Groups[1].Value }

    if ([string]::IsNullOrWhiteSpace($jsRelative)) {
        throw "Could not find portal JS reference in $PortalPageUrl"
    }

    $baseUri = [Uri]$PortalPageUrl
    $jsUri = [Uri]::new($baseUri, $jsRelative).AbsoluteUri
    $js = [string](Invoke-WebRequest -Uri $jsUri -TimeoutSec 15 -UseBasicParsing).Content

    $drPs = 1
    $drPid = '2'
    $drCalg = '12345678'

    $mPs = [regex]::Match($js, 'ps\s*=\s*(\d+)', 'IgnoreCase')
    if ($mPs.Success) { $drPs = [int]$mPs.Groups[1].Value }

    $mPid = [regex]::Match($js, 'pid\s*=\s*''([^'']+)''', 'IgnoreCase')
    if ($mPid.Success) { $drPid = $mPid.Groups[1].Value }

    $mCalg = [regex]::Match($js, 'calg\s*=\s*''([^'']+)''', 'IgnoreCase')
    if ($mCalg.Success) { $drCalg = $mCalg.Groups[1].Value }

    $mk = '123456'
    $mMk = [regex]::Match($html, 'name="0MKKey"\s+value="([^"]*)"', 'IgnoreCase')
    if ($mMk.Success -and -not [string]::IsNullOrWhiteSpace($mMk.Groups[1].Value)) {
        $mk = $mMk.Groups[1].Value
    }

    $para = '00'
    $mPara = [regex]::Match($html, 'name="para"\s+value="([^"]*)"', 'IgnoreCase')
    if ($mPara.Success -and -not [string]::IsNullOrWhiteSpace($mPara.Groups[1].Value)) {
        $para = $mPara.Groups[1].Value
    }

    $v6ip = ''
    $mv6 = [regex]::Match($html, 'name="v6ip"\s+value="([^"]*)"', 'IgnoreCase')
    if ($mv6.Success) { $v6ip = $mv6.Groups[1].Value }

    return @{
        submit_url = $PortalPageUrl
        ps = $drPs
        pid = $drPid
        calg = $drCalg
        mk = $mk
        para = $para
        v6ip = $v6ip
        js_url = $jsUri
    }
}

function Get-DrcomPayload {
    param(
        [string]$Username,
        [string]$Password,
        [hashtable]$DrcomCtx
    )

    $upass = ''
    $r2 = '0'

    if ([int]$DrcomCtx.ps -eq 0) {
        $upass = [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($Password))
    }
    else {
        $upass = (Get-Md5Hex -InputText ($DrcomCtx.pid + $Password + $DrcomCtx.calg)) + $DrcomCtx.calg + $DrcomCtx.pid
        $r2 = '1'
    }

    return @{
        DDDDD  = $Username
        upass  = $upass
        R1     = '0'
        R2     = $r2
        para   = $DrcomCtx.para
        '0MKKey' = $DrcomCtx.mk
        v6ip   = $DrcomCtx.v6ip
    }
}

function Test-LoginSuccess {
    param(
        [int]$StatusCode,
        [string]$Content,
        [hashtable]$SuccessMatch
    )

    if (-not $SuccessMatch) {
        return ($StatusCode -ge 200 -and $StatusCode -lt 300)
    }

    $statusOk = $true
    if ($SuccessMatch.ContainsKey('status_codes') -and $SuccessMatch.status_codes) {
        $statusOk = ($SuccessMatch.status_codes -contains $StatusCode)
    }

    $containsOk = $true
    if ($SuccessMatch.ContainsKey('contains_any') -and $SuccessMatch.contains_any) {
        $containsOk = $false
        foreach ($keyword in $SuccessMatch.contains_any) {
            if (-not [string]::IsNullOrWhiteSpace([string]$keyword) -and $Content -like "*$keyword*") {
                $containsOk = $true
                break
            }
        }
    }

    $excludesOk = $true
    if ($SuccessMatch.ContainsKey('not_contains_any') -and $SuccessMatch.not_contains_any) {
        foreach ($keyword in $SuccessMatch.not_contains_any) {
            if (-not [string]::IsNullOrWhiteSpace([string]$keyword) -and $Content -like "*$keyword*") {
                $excludesOk = $false
                break
            }
        }
    }

    return ($statusOk -and $containsOk -and $excludesOk)
}

try {
    if (-not (Test-Path -LiteralPath $ConfigPath)) {
        throw "Config file not found: $ConfigPath"
    }

    $configRaw = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
    $config = ConvertTo-NativeObject -InputObject $configRaw

    foreach ($required in @('max_retries', 'retry_interval_sec', 'interface_mode')) {
        if (-not $config.ContainsKey($required)) {
            throw "Missing required config key: $required"
        }
    }

    if ($config.interface_mode -eq 'ethernet_only' -and -not (Test-EthernetConnected)) {
        Write-StructuredLog -Level 'INFO' -Message 'Skip auth: no active ethernet adapter.' -Data @{}
        exit 0
    }

    $credential = Get-GenericCredential -Target $CredentialTarget
    $authMode = 'drcom_hfut'
    if ($config.ContainsKey('auth_mode') -and -not [string]::IsNullOrWhiteSpace([string]$config.auth_mode)) {
        $authMode = [string]$config.auth_mode
    }

    $headers = @{}
    if ($config.ContainsKey('request_headers') -and $config.request_headers) { $headers = $config.request_headers }

    $contentType = 'application/x-www-form-urlencoded'
    if ($config.ContainsKey('content_type') -and -not [string]::IsNullOrWhiteSpace([string]$config.content_type)) {
        $contentType = [string]$config.content_type
    }

    $maxRetries = [int]$config.max_retries
    $retryInterval = [int]$config.retry_interval_sec
    $successMatch = $null
    if ($config.ContainsKey('success_match') -and $config.success_match) { $successMatch = $config.success_match }

    for ($attempt = 1; $attempt -le $maxRetries; $attempt++) {
        try {
            $targetUrl = ''
            $body = $null

            if ($authMode -eq 'drcom_hfut') {
                $portalPageUrl = [string]$config.portal_page_url
                if ([string]::IsNullOrWhiteSpace($portalPageUrl)) {
                    throw 'auth_mode=drcom_hfut requires portal_page_url in config.'
                }

                $ctx = Get-DrcomPageContext -PortalPageUrl $portalPageUrl
                $targetUrl = [string]$ctx.submit_url
                $body = Get-DrcomPayload -Username $credential.username -Password $credential.password -DrcomCtx $ctx

                Write-StructuredLog -Level 'INFO' -Message 'Prepared drcom request context.' -Data @{
                    attempt = $attempt
                    ps = $ctx.ps
                    js_url = $ctx.js_url
                }
            }
            else {
                foreach ($required in @('portal_url', 'http_method', 'payload_template')) {
                    if (-not $config.ContainsKey($required)) {
                        throw "Missing required config key for template mode: $required"
                    }
                }

                $templateMap = @{ username = $credential.username; password = $credential.password }
                $targetUrl = [string]$config.portal_url
                $body = Resolve-Template -Value $config.payload_template -Map $templateMap
            }

            $method = 'POST'
            if ($config.ContainsKey('http_method') -and -not [string]::IsNullOrWhiteSpace([string]$config.http_method)) {
                $method = [string]$config.http_method
            }

            if ($contentType -like 'application/json*' -and ($body -isnot [string])) {
                $body = $body | ConvertTo-Json -Compress -Depth 10
            }

            $invokeParams = @{
                Uri         = $targetUrl
                Method      = $method
                Headers     = $headers
                Body        = $body
                ContentType = $contentType
                TimeoutSec  = 15
                ErrorAction = 'Stop'
            }
            if ($PSVersionTable.PSVersion.Major -lt 6) { $invokeParams['UseBasicParsing'] = $true }

            $response = Invoke-WebRequest @invokeParams
            $statusCode = [int]$response.StatusCode
            $content = [string]$response.Content
            $isSuccess = Test-LoginSuccess -StatusCode $statusCode -Content $content -SuccessMatch $successMatch

            if ($isSuccess) {
                Write-StructuredLog -Level 'INFO' -Message 'Campus auth succeeded.' -Data @{
                    attempt = $attempt
                    statusCode = $statusCode
                    auth_mode = $authMode
                }
                exit 0
            }

            Write-StructuredLog -Level 'WARN' -Message 'Campus auth response did not match success criteria.' -Data @{
                attempt = $attempt
                statusCode = $statusCode
            }
        }
        catch {
            Write-StructuredLog -Level 'ERROR' -Message 'Campus auth request failed.' -Data @{
                attempt = $attempt
                error = $_.Exception.Message
            }
        }

        if ($attempt -lt $maxRetries) {
            Start-Sleep -Seconds $retryInterval
        }
    }

    Write-StructuredLog -Level 'ERROR' -Message 'Campus auth failed after retries.' -Data @{ maxRetries = $maxRetries }
    exit 1
}
catch {
    Write-StructuredLog -Level 'ERROR' -Message 'Campus auth aborted.' -Data @{ error = $_.Exception.Message }
    exit 1
}
