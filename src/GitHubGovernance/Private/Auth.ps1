function ConvertTo-Base64Url {
    param([byte[]] $Bytes)
    return [Convert]::ToBase64String($Bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
}

function New-AppJwt {
    <#
    .SYNOPSIS
        Creates a short-lived (9 min) RS256 JWT for the GitHub App, signed with its private key (PEM).
    #>
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $header = @{ alg = 'RS256'; typ = 'JWT' } | ConvertTo-Json -Compress
    # iat 60s in the past to tolerate clock drift; GitHub allows max 10 minutes lifetime.
    $payload = @{ iat = $now - 60; exp = $now + 540; iss = $script:AppClientId } | ConvertTo-Json -Compress
    $unsigned = (ConvertTo-Base64Url ([Text.Encoding]::UTF8.GetBytes($header))) + '.' +
    (ConvertTo-Base64Url ([Text.Encoding]::UTF8.GetBytes($payload)))

    $rsa = [System.Security.Cryptography.RSA]::Create()
    try {
        $rsa.ImportFromPem($script:AppPrivateKey)
        $signature = $rsa.SignData([Text.Encoding]::UTF8.GetBytes($unsigned),
            [System.Security.Cryptography.HashAlgorithmName]::SHA256,
            [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)
    } finally {
        $rsa.Dispose()
    }
    return "$unsigned.$(ConvertTo-Base64Url $signature)"
}

function Get-InstallationToken {
    <#
    .SYNOPSIS
        Returns an installation token for 'enterprise' or 'org:<login>' (App mode), cached and refreshed
        5 minutes before expiry. Returns $null when the App is not installed on that target.
    #>
    param([Parameter(Mandatory)] [string] $Scope)

    $cached = $script:TokenCache[$Scope]
    if ($cached -and $cached.ExpiresAt -gt [DateTimeOffset]::UtcNow.AddMinutes(5)) {
        return $cached.Token
    }
    if ($cached -and $null -eq $cached.Token) {
        return $null
    }   # known "not installed"

    $jwtHeaders = @{
        Authorization = "Bearer $(New-AppJwt)"
        Accept = 'application/vnd.github+json'
        'X-GitHub-Api-Version' = '2022-11-28'
        'User-Agent' = 'Export-GitHubEnterpriseDocs'
    }
    $lookup = if ($Scope -eq 'enterprise') {
        "enterprises/$($script:EnterpriseSlug)/installation"
    } elseif ($script:Connection.Scope -eq 'user' -and $Scope -eq "org:$($script:Connection.Account)") {
        "users/$($script:Connection.Account)/installation"
    } else {
        "orgs/$($Scope.Substring(4))/installation"
    }

    try {
        $installation = Invoke-RestMethod -Uri "$($script:ApiBaseUrl)/$lookup" -Headers $jwtHeaders -Method Get -ErrorAction Stop
    } catch {
        $response = $_.Exception.PSObject.Properties['Response']
        $status = if ($response -and $response.Value) {
            [int]$response.Value.StatusCode
        } else {
            $null
        }
        if ($status -in 403, 404) {
            Write-Warning "GitHub App is not installed on $Scope (or not reachable): $($_.Exception.Message)"
            $script:TokenCache[$Scope] = @{ Token = $null; ExpiresAt = [DateTimeOffset]::MaxValue }
            return $null
        }
        throw
    }

    if ($script:Connection.Scope -in 'organization', 'user' -and $Scope -eq "org:$($script:Connection.Account)" -and
        $installation.repository_selection -ne 'all') {
        throw "Install the GitHub App on all repositories for $($script:Connection.Account); selected repositories cannot provide a complete inventory."
    }
    $response = Invoke-RestMethod -Uri "$($script:ApiBaseUrl)/app/installations/$($installation.id)/access_tokens" -Headers $jwtHeaders -Method Post -ErrorAction Stop
    $script:TokenCache[$Scope] = @{ Token = $response.token; ExpiresAt = [DateTimeOffset]::Parse($response.expires_at) }
    return $response.token
}

function Get-ScopeForPath {
    # Maps a REST path to the installation that can serve it: orgs/<org>/..., repos/<org>/... -> org; rest -> enterprise.
    param([string] $Path)
    if ($Path -match '^/?(orgs|repos)/([^/?]+)') {
        return "org:$($Matches[2])"
    }
    if ($Path -match '^/?installation/repositories(?:[/?]|$)' -and $script:Connection.Scope -eq 'user') {
        return "org:$($script:Connection.Account)"
    }
    return 'enterprise'
}

function Get-RequestHeaders {
    # Returns request headers for a scope, or $null when no credential is available for it.
    param([string] $Scope)
    $token = if ($script:AuthMode -eq 'App') {
        Get-InstallationToken -Scope $Scope
    } else {
        $script:PatToken
    }
    if (-not $token) {
        return $null
    }
    return @{
        Authorization = "Bearer $token"
        Accept = 'application/vnd.github+json'
        'X-GitHub-Api-Version' = '2022-11-28'
        'User-Agent' = 'Export-GitHubEnterpriseDocs'
    }
}

function Assert-GHConnection {
    # Throws when Connect-GHGovernance has not been called in this session.
    if (-not $script:Connection) {
        throw 'Not connected. Run Connect-GHGovernance first.'
    }
}
