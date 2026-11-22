param($ComplianceContext, [switch] $PolicyOnly)

$PolicyCheck = {
    param($Snap, $Params)
    $settings = Get-Section $Snap 'actionsPermissions'
    if ($null -eq $settings) { return NotEvaluated 'actionsPermissions is not accessible.' }
    $value = Get-Prop $settings[0] 'sha_pinning_required'
    if ($value -isnot [bool]) { return NotEvaluated 'sha_pinning_required was not returned.' }
    if ($value -eq $true) { Pass } else { Fail 'Require Actions to use immutable SHA references does not meet the configured requirement.' }
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
    It 'org.actions-sha-pinning: Require Actions to use immutable SHA references' {
        $result = if ($ComplianceContext) {
            $ComplianceContext.Result
        } else {
            Invoke-GHComplianceCheck -CheckId 'org.actions-sha-pinning' -Organization $env:GHE_ORGANIZATION -Repository $env:GHE_REPOSITORY `
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
