function Invoke-GHRestMethod {
    <#
    .SYNOPSIS
        Calls any GitHub REST GET endpoint with the right credential (enterprise or organization
        installation in App mode) and returns the data. Useful for ad-hoc queries.

    .EXAMPLE
        Invoke-GHRestMethod 'orgs/my-org/teams' -Paginate
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)] [string] $Path,
        [switch] $Paginate,
        [string] $ItemProperty
    )
    Assert-GHConnection
    $result = Invoke-GitHubRest -Path $Path -Paginate:$Paginate -ItemProperty $ItemProperty
    Resolve-SectionData -Result $result -What "GET $Path" -Cmdlet $PSCmdlet
}
