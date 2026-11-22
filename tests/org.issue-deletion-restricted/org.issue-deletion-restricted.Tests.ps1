param($ComplianceContext, [switch] $PolicyOnly)

$PolicyCheck = {
    param($Snap, $Params)
    $section = Get-Section $Snap 'settings'
    if ($null -eq $section) { return NotEvaluated 'Organization settings are not available.' }
    $value = Get-Prop $section[0] 'members_can_delete_issues'
    if ($value -isnot [bool]) { return NotEvaluated 'members_can_delete_issues was not returned as a boolean.' }
    if ($value -eq $false) { Pass } else { Fail 'Restrict issue deletion does not meet the configured requirement.' }
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
    It 'org.issue-deletion-restricted: Restrict issue deletion' {
        $result = if ($ComplianceContext) {
            $ComplianceContext.Result
        } else {
            Invoke-GHComplianceCheck -CheckId 'org.issue-deletion-restricted' -Organization $env:GHE_ORGANIZATION -Repository $env:GHE_REPOSITORY `
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
