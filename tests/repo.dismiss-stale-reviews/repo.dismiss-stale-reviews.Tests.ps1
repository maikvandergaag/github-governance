param($ComplianceContext, [switch] $PolicyOnly)

$PolicyCheck = {
    param($Repo, $Snap, $CodeOwners, $Params)
    Test-GHBranchRule $Repo 'pull_request' { param($item) $value = Get-Prop $item 'parameters.dismiss_stale_reviews_on_push'; if ($value -isnot [bool]) { return $null }; $value -eq $true } `
        { param($item) $value = Get-Prop $item 'required_pull_request_reviews.dismiss_stale_reviews'; if ($value -isnot [bool]) { return $null }; $value -eq $true } 'Dismiss stale pull request approvals is not enforced on the default branch.'
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
    It 'repo.dismiss-stale-reviews: Dismiss stale pull request approvals' {
        $result = if ($ComplianceContext) {
            $ComplianceContext.Result
        } else {
            Invoke-GHComplianceCheck -CheckId 'repo.dismiss-stale-reviews' -Organization $env:GHE_ORGANIZATION -Repository $env:GHE_REPOSITORY `
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
