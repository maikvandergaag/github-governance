function Get-GHRepository {
    <#
    .SYNOPSIS
        Repositories of an organization, including security_and_analysis when the credential has
        admin access. Archived repositories are excluded unless -IncludeArchived is used.
    .EXAMPLE
        Get-GHRepository my-org | Where-Object visibility -eq 'public'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('login')]
        [string[]] $Organization,
        [switch] $IncludeArchived
    )
    begin {
        Assert-GHConnection
    }
    process {
        foreach ($org in $Organization) {
            $r = if ($script:Connection.Scope -eq 'user' -and $org -eq $script:Connection.Account) {
                $result = Invoke-GitHubRest 'installation/repositories' -Paginate -ItemProperty 'repositories'
                if ($result.Ok) {
                    $result.Data = @($result.Data | Where-Object { $_.owner.login -eq $org })
                }
                $result
            } else {
                Invoke-GitHubRest "orgs/$org/repos?type=all" -Paginate
            }
            Resolve-SectionData -Result $r -What "repositories for $org" -Cmdlet $PSCmdlet |
                Where-Object { $IncludeArchived -or -not $_.archived }
        }
    }
}
