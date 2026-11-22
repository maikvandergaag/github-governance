param($ComplianceContext, [switch] $PolicyOnly)

$PolicyCheck = {
    param($Snap, $Params)
    $settings = Get-Section $Snap 'settings'
    if ($null -eq $settings) { return NotEvaluated 'Organization settings not available.' }
    $public = Get-Prop $settings[0] 'members_can_create_public_repositories'
    $private = Get-Prop $settings[0] 'members_can_create_private_repositories'
    if ($public -isnot [bool] -or $private -isnot [bool]) {
        return NotEvaluated 'Public and private repository creation settings were not both returned as booleans.'
    }
    if ($public -or $private) { return Fail 'Members can create public or private repositories.' }
    Pass
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
    It 'org.repo-creation-restricted: Member repository creation is restricted' {
        $result = if ($ComplianceContext) {
            $ComplianceContext.Result
        } else {
            Invoke-GHComplianceCheck -CheckId 'org.repo-creation-restricted' -Organization $env:GHE_ORGANIZATION -Repository $env:GHE_REPOSITORY `
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
