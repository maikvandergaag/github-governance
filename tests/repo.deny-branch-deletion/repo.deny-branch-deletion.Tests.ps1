param($ComplianceContext, [switch] $PolicyOnly)

$PolicyCheck = {
    param($Repo, $Snap, $CodeOwners, $Params)
    Test-GHBranchRule $Repo 'deletion' { param($item) $true } `
        { param($item) $value = Get-Prop $item 'allow_deletions.enabled'; if ($value -isnot [bool]) { return $null }; $value -eq $false } 'Deny default branch deletion is not enforced on the default branch.'
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
    It 'repo.deny-branch-deletion: Deny default branch deletion' {
        $result = if ($ComplianceContext) {
            $ComplianceContext.Result
        } else {
            Invoke-GHComplianceCheck -CheckId 'repo.deny-branch-deletion' -Organization $env:GHE_ORGANIZATION -Repository $env:GHE_REPOSITORY `
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
