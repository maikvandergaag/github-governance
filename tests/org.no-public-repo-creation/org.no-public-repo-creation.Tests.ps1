param($ComplianceContext, [switch] $PolicyOnly)

$PolicyCheck = {
    param($Snap, $Params)
    $settings = Get-Section $Snap 'settings'
    if ($null -eq $settings) {
        return NotEvaluated 'Organization settings not available.'
    }
    $value = Get-Prop $settings[0] 'members_can_create_public_repositories'
    if ($null -eq $value) {
        return NotEvaluated 'members_can_create_public_repositories not returned.'
    }
    if (-not $value) {
        Pass
    } else {
        Fail 'Members can create public repositories.'
    }
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
    It 'org.no-public-repo-creation: Members cannot create public repositories' {
        $result = if ($ComplianceContext) {
            $ComplianceContext.Result
        } else {
            Invoke-GHComplianceCheck -CheckId 'org.no-public-repo-creation' -Organization $env:GHE_ORGANIZATION -Repository $env:GHE_REPOSITORY `
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
