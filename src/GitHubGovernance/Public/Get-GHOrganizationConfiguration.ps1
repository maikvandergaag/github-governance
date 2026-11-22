function Get-GHOrganizationConfiguration {
    <#
    .SYNOPSIS
        Full organization snapshot as used by Export-GHDocumentation and Test-GHCompliance.
        Every section is an object with Ok/Status/Data, so missing permissions are explicit.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('login')]
        [string[]] $Organization,
        # Skip the repository inventory (and therefore CODEOWNERS).
        [switch] $SkipRepositories,
        [switch] $SkipCodeOwners
    )
    begin {
        Assert-GHConnection
    }
    process {
        foreach ($org in $Organization) {
            Write-Verbose "Collecting $org ..."
            $snapshot = [ordered]@{ login = $org }
            foreach ($name in $script:OrgSections.Keys) {
                $snapshot[$name] = Get-OrgSection -Org $org -Name $name
            }
            $rulesetDetailsComplete = $false
            $snapshot.rulesetDetails = @(Get-OrgRulesetDetails -Org $org -RulesetsResult $snapshot.rulesets -DetailsComplete ([ref]$rulesetDetailsComplete))
            $snapshot.rulesetDetailsComplete = $rulesetDetailsComplete
            $snapshot.repositories = $null
            $snapshot.codeOwners = $null
            if (-not $SkipRepositories) {
                $snapshot.repositories = Invoke-GitHubRest "orgs/$org/repos?type=all" -Paginate
                if ($snapshot.repositories.Ok) {
                    foreach ($repository in @($snapshot.repositories.Data | Where-Object { -not $_.archived })) {
                        $evidence = Get-GHBranchEvidence -Organization ([uri]::EscapeDataString($org)) `
                            -Repository ([uri]::EscapeDataString($repository.name)) -DefaultBranch (Get-Prop $repository 'default_branch')
                        $repository | Add-Member -NotePropertyName complianceBranchEvidence -NotePropertyValue $evidence -Force
                        $rootFiles = Get-GHRootFileEvidence -Organization ([uri]::EscapeDataString($org)) `
                            -Repository ([uri]::EscapeDataString($repository.name)) -DefaultBranch (Get-Prop $repository 'default_branch')
                        $repository | Add-Member -NotePropertyName complianceGitAttributes -NotePropertyValue (Get-Prop $rootFiles 'gitAttributes') -Force
                        $repository | Add-Member -NotePropertyName complianceGitIgnore -NotePropertyValue (Get-Prop $rootFiles 'gitIgnore') -Force
                        $repository | Add-Member -NotePropertyName complianceReadme -NotePropertyValue (Get-Prop $rootFiles 'readme') -Force
                    }
                }
                if (-not $SkipCodeOwners -and $snapshot.repositories.Ok) {
                    $active = @($snapshot.repositories.Data | Where-Object { -not $_.archived } | ForEach-Object name)
                    $snapshot.codeOwners = @(Get-CodeOwnersBatch -Org $org -Repositories $active)
                }
            }
            [pscustomobject]$snapshot
        }
    }
}
