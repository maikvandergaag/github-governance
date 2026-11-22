param($ComplianceContext, [switch] $PolicyOnly)

$PolicyCheck = {
    param($Repo, $Snap, $CodeOwners, $Params)
    Test-GHBranchRule $Repo 'update' { param($item) $true } {
        param($item)
        $restriction = Get-Prop $item 'restrictions'
        if ($null -eq $restriction) { return $false }
        foreach ($kind in @('users', 'teams', 'apps')) {
            if (-not $restriction.PSObject.Properties[$kind] -or $null -eq $restriction.$kind) { return $null }
        }
        (@($restriction.users).Count + @($restriction.teams).Count + @($restriction.apps).Count) -gt 0
    } 'Default branch updates are not restricted to selected actors.'
}

if ($PolicyOnly) {
    return $PolicyCheck
}

BeforeAll {
    if (-not $ComplianceContext -and -not (Get-Module GitHubGovernance)) {
        throw 'Import the GitHubGovernance module and connect a GitHub App before running compliance tests.'
    }
}

Describe 'GitHub compliance' -Tag 'compliance', 'repo' {
    It 'repo.restrict-branch-updates: Restrict default branch updates' {
        $result = if ($ComplianceContext) {
            $ComplianceContext.Result
        } else {
            Invoke-GHComplianceCheck -CheckId 'repo.restrict-branch-updates' -Organization $env:GHE_ORGANIZATION -Repository $env:GHE_REPOSITORY `
                -TestsPath (Split-Path -Parent $PSScriptRoot)
        }
        if ($result.status -in 'na', 'notEvaluated') {
            Set-ItResult -Skipped -Because $result.detail
            return
        }
        $detail = if ($result.status -eq 'pass') {
            ''
        } else {
            [string]$result.detail
        }
        $result.status | Should -Be 'pass' -Because $detail
    }
}
