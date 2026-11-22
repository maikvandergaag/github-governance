function Get-GHCodeOwners {
    <#
    .SYNOPSIS
        CODEOWNERS per repository: location (same precedence as GitHub: .github/, root, docs/),
        parsed rules (line, pattern, owners) and validation errors reported by GitHub.
        Without -Repository all active (non-archived) repositories of the organization are read.
    .EXAMPLE
        Get-GHCodeOwners my-org | Where-Object { -not $_.path }      # repositories without CODEOWNERS
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipelineByPropertyName)]
        [Alias('login')]
        [string] $Organization,
        [string[]] $Repository
    )
    begin {
        Assert-GHConnection
    }
    process {
        if (-not $Repository) {
            $Repository = @(Get-GHRepository -Organization $Organization | ForEach-Object name)
        }
        Get-CodeOwnersBatch -Org $Organization -Repositories $Repository
    }
}
