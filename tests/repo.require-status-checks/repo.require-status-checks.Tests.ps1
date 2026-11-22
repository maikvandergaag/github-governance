param($ComplianceContext, [switch] $PolicyOnly)

$PolicyCheck = {
    param($Repo, $Snap, $CodeOwners, $Params)
    Test-GHBranchRule $Repo 'required_status_checks' {
        param($item)
        $parent = Get-Prop $item 'parameters'
        if (-not $parent -or -not $parent.PSObject.Properties['required_status_checks'] -or $null -eq $parent.required_status_checks) { return $null }
        @($parent.required_status_checks).Count -gt 0
    } {
        param($item)
        $parent = Get-Prop $item 'required_status_checks'
        if ($null -eq $parent) { return $false }
        if (-not $parent.PSObject.Properties['checks'] -or $null -eq $parent.checks) { return $null }
        @($parent.checks).Count -gt 0
    } 'Require status checks before merging is not enforced on the default branch.'
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
    It 'repo.require-status-checks: Require status checks before merging' {
        $result = if ($ComplianceContext) {
            $ComplianceContext.Result
        } else {
            Invoke-GHComplianceCheck -CheckId 'repo.require-status-checks' -Organization $env:GHE_ORGANIZATION -Repository $env:GHE_REPOSITORY `
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
