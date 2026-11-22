param($ComplianceContext, [switch] $PolicyOnly)

$PolicyCheck = {
    param($Snap, $Params)
    $hooks = Get-Section $Snap 'webhooks'
    if ($null -eq $hooks) {
        return NotEvaluated 'Webhooks not available.'
    }
    $insecure = @($hooks | Where-Object { (Get-Prop $_ 'config.insecure_ssl') -eq '1' } | ForEach-Object { Get-Prop $_ 'config.url' })
    if ($insecure.Count -eq 0) {
        Pass
    } else {
        Fail "TLS verification disabled for: $($insecure -join ', ')"
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
