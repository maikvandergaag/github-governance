param($ComplianceContext, [switch] $PolicyOnly)

$PolicyCheck = {
    param($Repo, $Snap, $CodeOwners, $Params)
    Test-GHBranchRule $Repo 'pull_request' { param($item) $value = Get-Prop $item 'parameters.required_approving_review_count'; if ($null -eq $value) { return $null }; if ($value -isnot [int] -and $value -isnot [long]) { return $null }; $value -ge 2 } `
        { param($item) $value = Get-Prop $item 'required_pull_request_reviews.required_approving_review_count'; if ($null -eq $value) { return $null }; if ($value -isnot [int] -and $value -isnot [long]) { return $null }; $value -ge 2 } 'Require at least two pull request approvals is not enforced on the default branch.'
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
    It 'repo.two-approvals: Require at least two pull request approvals' {
        $result = if ($ComplianceContext) {
            $ComplianceContext.Result
        } else {
            Invoke-GHComplianceCheck -CheckId 'repo.two-approvals' -Organization $env:GHE_ORGANIZATION -Repository $env:GHE_REPOSITORY `
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
