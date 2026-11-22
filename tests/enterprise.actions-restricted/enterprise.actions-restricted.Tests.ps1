param($ComplianceContext, [switch] $PolicyOnly)

$PolicyCheck = {
    param($Snap, $Params)
    $actions = Get-Section $Snap 'actionsPermissions'
    if ($null -eq $actions) {
        return NotEvaluated 'Enterprise Actions permissions not available.'
    }
    $value = Get-Prop $actions[0] 'allowed_actions'
    if ($null -eq $value) {
        if ((Get-Prop $actions[0] 'enabled_organizations') -eq 'none') {
            return Pass
        }
        return NotEvaluated 'Allowed actions setting was not returned.'
    }
    if ($value -in @($Params.allowed)) {
        Pass
    } else {
        Fail "Allowed actions is ``$value`` (allowed: $(@($Params.allowed) -join ', '))."
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

Describe 'GitHub compliance' -Tag 'compliance', 'enterprise' {
    It 'enterprise.actions-restricted: GitHub Actions are restricted at enterprise level' {
        $result = if ($ComplianceContext) {
            $ComplianceContext.Result
        } else {
            Invoke-GHComplianceCheck -CheckId 'enterprise.actions-restricted' -Organization $env:GHE_ORGANIZATION -Repository $env:GHE_REPOSITORY `
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
