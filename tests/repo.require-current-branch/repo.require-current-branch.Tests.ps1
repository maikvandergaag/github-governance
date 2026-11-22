param($ComplianceContext, [switch] $PolicyOnly)

$PolicyCheck = {
    param($Repo, $Snap, $CodeOwners, $Params)
    Test-GHBranchRule $Repo 'required_status_checks' { param($item) $value = Get-Prop $item 'parameters.strict_required_status_checks_policy'; if ($value -isnot [bool]) { return $null }; $value -eq $true } `
        { param($item) $value = Get-Prop $item 'required_status_checks.strict'; if ($value -isnot [bool]) { return $null }; $value -eq $true } 'Require branches to be up to date is not enforced on the default branch.'
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
    It 'repo.require-current-branch: Require branches to be up to date' {
        $result = if ($ComplianceContext) {
            $ComplianceContext.Result
        } else {
            Invoke-GHComplianceCheck -CheckId 'repo.require-current-branch' -Organization $env:GHE_ORGANIZATION -Repository $env:GHE_REPOSITORY `
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
