function Connect-GHGovernance {
    <#
    .SYNOPSIS
        Sets up an enterprise, standalone organization, or personal account connection.

    .DESCRIPTION
        Two authentication modes:
          - GitHub App (preferred): -AppClientId + -AppPrivateKey. The App must be installed on the
            target account and all its repositories; enterprise mode also needs an enterprise
            installation. One token is minted per installation, cached and refreshed automatically.
          - Classic PAT: -Token.
        Without parameters the environment variables GH_APP_CLIENT_ID / GH_APP_PRIVATE_KEY or
        GH_ENTERPRISE_TOKEN are used.

    .EXAMPLE
        Connect-GHGovernance -Enterprise contoso -AppClientId Iv23li... -AppPrivateKey (Get-Content ./app.pem -Raw)

    .EXAMPLE
        Connect-GHGovernance -Enterprise contoso -Token $env:GH_ENTERPRISE_TOKEN -ApiBaseUrl https://api.contoso.ghe.com

    .EXAMPLE
        Connect-GHGovernance -Organization my-org -AppClientId $clientId -AppPrivateKey $key

    .EXAMPLE
        Connect-GHGovernance -User my-login -AppClientId $clientId -AppPrivateKey $key
    #>
    [CmdletBinding(DefaultParameterSetName = 'Environment')]
    param(
        [string] $Enterprise,
        [string] $Organization,
        [string] $User,

        [Parameter(Mandatory, ParameterSetName = 'App')]
        [string] $AppClientId,

        [Parameter(Mandatory, ParameterSetName = 'App')]
        [string] $AppPrivateKey,

        [Parameter(Mandatory, ParameterSetName = 'Pat')]
        [string] $Token,

        # https://api.github.com, or https://api.<subdomain>.ghe.com for GHE.com data residency.
        [string] $ApiBaseUrl = 'https://api.github.com'
    )

    $scopes = @($Enterprise, $Organization, $User | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($scopes.Count -ne 1) {
        throw 'Specify exactly one of -Enterprise, -Organization, or -User.'
    }
    $scopeType = if ($Enterprise) { 'enterprise' } elseif ($Organization) { 'organization' } else { 'user' }
    $account = $scopes[0]
    if ($scopeType -ne 'enterprise' -and $account -notmatch '^[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,37}[a-zA-Z0-9])?$') {
        throw "Invalid GitHub account or enterprise name: '$account'."
    }
    if ($PSCmdlet.ParameterSetName -eq 'Environment') {
        if ($env:GH_APP_CLIENT_ID -and $env:GH_APP_PRIVATE_KEY) {
            $AppClientId = $env:GH_APP_CLIENT_ID; $AppPrivateKey = $env:GH_APP_PRIVATE_KEY
        } elseif ($env:GH_ENTERPRISE_TOKEN) {
            $Token = $env:GH_ENTERPRISE_TOKEN
        } else {
            throw 'No credentials. Pass -AppClientId/-AppPrivateKey or -Token, or set GH_APP_CLIENT_ID + GH_APP_PRIVATE_KEY or GH_ENTERPRISE_TOKEN.'
        }
    }

    if ($AppClientId -and $AppPrivateKey) {
        $api = $null
        if (-not [uri]::TryCreate($ApiBaseUrl, [UriKind]::Absolute, [ref]$api) -or
            $api.Scheme -ne 'https' -or -not $api.Host -or $api.UserInfo -or $api.Query -or $api.Fragment) {
            throw 'ApiBaseUrl must be an HTTPS URL without user information, a query, or a fragment for GitHub App authentication.'
        }
    }

    $script:ApiBaseUrl = $ApiBaseUrl.TrimEnd('/')
    $script:GraphQLUrl = "$($script:ApiBaseUrl)/graphql"
    $script:EnterpriseSlug = $Enterprise
    $script:TokenCache = @{}
    $script:AppClientId = $null; $script:AppPrivateKey = $null; $script:PatToken = $null

    if ($AppClientId -and $AppPrivateKey) {
        $script:AuthMode = 'App'
        $script:AppClientId = $AppClientId
        $script:AppPrivateKey = $AppPrivateKey
    } else {
        $script:AuthMode = 'Pat'
        $script:PatToken = $Token
    }

    # Public, secret-free view of the connection.
    $script:Connection = [pscustomobject]@{
        Enterprise = $Enterprise
        Scope = $scopeType
        Account = $account
        ApiBaseUrl = $script:ApiBaseUrl
        AuthMode = $script:AuthMode
    }

    if ($script:AuthMode -eq 'App') {
        $installationScope = if ($scopeType -eq 'enterprise') { 'enterprise' } else { "org:$account" }
        try {
            if (-not (Get-InstallationToken -Scope $installationScope)) {
                if ($scopeType -ne 'enterprise') {
                    throw "The GitHub App is not installed on $scopeType '$account'."
                }
                Write-Warning "The GitHub App is not installed on enterprise '$Enterprise'. Enterprise-level data will be unavailable."
            }
        } catch {
            Disconnect-GHGovernance
            throw
        }
    }
    return $script:Connection
}
