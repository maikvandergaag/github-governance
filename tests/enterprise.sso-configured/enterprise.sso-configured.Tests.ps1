param($ComplianceContext, [switch] $PolicyOnly)

$PolicyCheck = {
    param($Snap, $Params)
    $saml = Get-OwnerInfoField $Snap 'samlIdentityProvider'
    $oidc = Get-OwnerInfoField $Snap 'oidcProvider'
    if ($saml.Readable -and $saml.Value) {
        return Pass
    }
    if ($oidc.Readable -and $oidc.Value) {
        return Pass
    }
    if (-not $saml.Readable -or -not $oidc.Readable) {
        return NotEvaluated 'Identity provider configuration not readable.'
    }
    Fail 'No SAML or OIDC identity provider configured at enterprise level.'
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
    It 'enterprise.sso-configured: Single sign-on is configured' {
        $result = if ($ComplianceContext) {
            $ComplianceContext.Result
        } else {
            Invoke-GHComplianceCheck -CheckId 'enterprise.sso-configured' -Organization $env:GHE_ORGANIZATION -Repository $env:GHE_REPOSITORY `
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
