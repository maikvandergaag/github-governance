param($ComplianceContext, [switch] $PolicyOnly)

$PolicyCheck = {
    param($Snap, $Params)
    $items = Get-Section $Snap 'actionsSecrets'
    if ($null -eq $items) { return NotEvaluated 'actionsSecrets is not accessible.' }
    $count = 0
    foreach ($item in $items) {
        $value = Get-Prop $item 'visibility'
        if ($value -notin @('all', 'selected', 'private')) { return NotEvaluated 'visibility was not returned for an item.' }
        if ($value -eq 'all') { $count++ }
    }
    if ($count -gt 0) { Fail "$count item(s) have broader access than this policy allows." } else { Pass }
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
    It 'org.secrets-limited-repositories: Limit organization Actions secrets' {
        $result = if ($ComplianceContext) {
            $ComplianceContext.Result
        } else {
            Invoke-GHComplianceCheck -CheckId 'org.secrets-limited-repositories' -Organization $env:GHE_ORGANIZATION -Repository $env:GHE_REPOSITORY `
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
