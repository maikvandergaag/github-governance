param($ComplianceContext, [switch] $PolicyOnly)

$PolicyCheck = {
    param($Snap, $Params)
    $settings = Get-Section $Snap 'actionsWorkflowPermissions'
    if ($null -eq $settings) { return NotEvaluated 'Workflow permissions are not accessible.' }
    $value = Get-Prop $settings[0] 'default_workflow_permissions'
    if ($value -notin @('read', 'write')) { return NotEvaluated 'default_workflow_permissions was not returned.' }
    if ($value -eq 'read') { Pass } else { Fail 'Restrict default workflow token permissions does not meet the configured requirement.' }
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
    It 'org.actions-token-read-only: Restrict default workflow token permissions' {
        $result = if ($ComplianceContext) {
            $ComplianceContext.Result
        } else {
            Invoke-GHComplianceCheck -CheckId 'org.actions-token-read-only' -Organization $env:GHE_ORGANIZATION -Repository $env:GHE_REPOSITORY `
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
