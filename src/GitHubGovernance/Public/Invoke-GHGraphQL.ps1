function Invoke-GHGraphQL {
    <#
    .SYNOPSIS
        Runs a GraphQL query. -Organization selects that organization's installation in App mode;
        otherwise the connected account's installation (or the PAT) is used.

    .EXAMPLE
        Invoke-GHGraphQL -Query 'query($o:String!){ organization(login:$o){ name } }' -Variables @{ o = 'my-org' } -Organization my-org
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Query,
        [hashtable] $Variables = @{},
        [string] $Organization
    )
    Assert-GHConnection
    $scope = if ($Organization) {
        "org:$Organization"
    } elseif ($script:Connection.Scope -ne 'enterprise') {
        "org:$($script:Connection.Account)"
    } else {
        'enterprise'
    }
    Invoke-GitHubGraphQL -Query $Query -Variables $Variables -Scope $scope
}
