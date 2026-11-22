function Get-GHEnterprisePolicy {
    <#
    .SYNOPSIS
        Enterprise policies and access settings: repository policies, 2FA, SAML/OIDC, IP allow list,
        owners, member/license counts (GraphQL ownerInfo). Policy values of NO_POLICY mean that
        organizations decide themselves.
    #>
    [CmdletBinding()]
    param()
    Assert-GHConnection
    $graph = Get-EnterpriseGraph
    if (-not $graph.Ok) {
        Write-Error 'Enterprise policies not available (credential needs enterprise owner rights / Enterprise settings permission).'; return
    }
    if (@($graph.ErrorPaths).Count) {
        Write-Warning "Not readable with this credential: $($graph.ErrorPaths -join ', ')"
    }
    $graph.Data
}
