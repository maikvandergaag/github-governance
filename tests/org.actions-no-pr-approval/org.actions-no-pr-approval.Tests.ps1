param($ComplianceContext, [switch] $PolicyOnly)

$PolicyCheck = {
    param($Snap, $Params)
    $settings = Get-Section $Snap 'actionsWorkflowPermissions'
    if ($null -eq $settings) { return NotEvaluated 'Workflow permissions are not accessible.' }
    $value = Get-Prop $settings[0] 'can_approve_pull_request_reviews'
    if ($value -isnot [bool]) { return NotEvaluated 'can_approve_pull_request_reviews was not returned.' }
    if ($value -eq $false) { Pass } else { Fail 'Disallow workflow pull request approvals does not meet the configured requirement.' }
}

if ($PolicyOnly) {
    return $PolicyCheck
}

BeforeAll {
    if (-not $ComplianceContext -and -not (Get-Module GitHubGovernance)) {
        throw 'Import the GitHubGovernance module and connect a GitHub App before running compliance tests.'
    }
}

Describe 'GitHub compliance' -Tag 'compliance', 'org' {
    It 'org.actions-no-pr-approval: Disallow workflow pull request approvals' {
        $result = if ($ComplianceContext) {
            $ComplianceContext.Result
        } else {
            Invoke-GHComplianceCheck -CheckId 'org.actions-no-pr-approval' -Organization $env:GHE_ORGANIZATION -Repository $env:GHE_REPOSITORY `
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
