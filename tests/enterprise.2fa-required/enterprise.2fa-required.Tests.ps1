param($ComplianceContext, [switch] $PolicyOnly)

$PolicyCheck = {
    param($Snap, $Params)
    $setting = Get-OwnerInfoField $Snap 'twoFactorRequiredSetting'
    if (-not $setting.Readable) {
        return NotEvaluated 'The enterprise 2FA setting could not be read from GitHub.'
    }
    if ($null -eq $setting.Value) {
        return NotEvaluated 'The enterprise 2FA setting was not returned.'
    }
    if ($setting.Value -eq 'ENABLED') {
        return Pass
    }
    if ($setting.Value -eq 'NO_POLICY') {
        return Fail '2FA is not enforced at enterprise level; organizations decide.'
    }

    Fail "2FA requirement is $($setting.Value); expected ENABLED."
}


if ($PolicyOnly) {
    return $PolicyCheck
}

BeforeAll {
    if (-not $ComplianceContext -and -not (Get-Module GitHubGovernance)) {
        throw 'Import the GitHubGovernance module and connect a GitHub App before running compliance tests.'
    }
}

Describe 'Enterprise authentication' -Tag 'enterprise', 'security' {
    It 'enterprise.2fa-required: Two-factor authentication is required enterprise-wide' {
        $result = if ($ComplianceContext) {
            $ComplianceContext.Result
        } else {
            Invoke-GHComplianceCheck -CheckId 'enterprise.2fa-required' -Organization $env:GHE_ORGANIZATION -Repository $env:GHE_REPOSITORY `
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
