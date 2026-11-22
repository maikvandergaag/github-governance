param($ComplianceContext, [switch] $PolicyOnly)

$PolicyCheck = {
    param($Snap, $Params)
    Test-GHSecurityDefault $Snap 'secret_scanning' 'Secret scanning'
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
    It 'org.secret-scanning-new-repos: Secret scanning is enabled for new repositories' {
        $result = if ($ComplianceContext) {
            $ComplianceContext.Result
        } else {
            Invoke-GHComplianceCheck -CheckId 'org.secret-scanning-new-repos' -Organization $env:GHE_ORGANIZATION -Repository $env:GHE_REPOSITORY `
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
