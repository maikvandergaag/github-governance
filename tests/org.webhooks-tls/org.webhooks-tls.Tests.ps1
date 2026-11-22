param($ComplianceContext, [switch] $PolicyOnly)

$PolicyCheck = {
    param($Snap, $Params)
    $hooks = Get-Section $Snap 'webhooks'
    if ($null -eq $hooks) {
        return NotEvaluated 'Webhooks not available.'
    }
    $insecure = @()
    foreach ($hook in $hooks) {
        $url = Get-Prop $hook 'config.url'
        $verify = Get-Prop $hook 'config.insecure_ssl'
        $uri = $null
        if ([string]::IsNullOrWhiteSpace($url) -or -not [uri]::TryCreate($url, [UriKind]::Absolute, [ref]$uri) -or
            [string]$verify -notin @('0', '1')) {
            return NotEvaluated 'A webhook URL or its TLS verification setting was not returned.'
        }
        if ($uri.Scheme -ne 'https' -or [string]$verify -eq '1') { $insecure += $url }
    }
    if ($insecure.Count -eq 0) {
        Pass
    } else {
        Fail "HTTPS or TLS verification is not enabled for: $($insecure -join ', ')"
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
    It 'org.webhooks-tls: Webhooks verify TLS certificates' {
        $result = if ($ComplianceContext) {
            $ComplianceContext.Result
        } else {
            Invoke-GHComplianceCheck -CheckId 'org.webhooks-tls' -Organization $env:GHE_ORGANIZATION -Repository $env:GHE_REPOSITORY `
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
