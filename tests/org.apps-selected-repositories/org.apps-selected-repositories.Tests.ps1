param($ComplianceContext, [switch] $PolicyOnly)

$PolicyCheck = {
    param($Snap, $Params)
    $items = Get-Section $Snap 'installations'
    if ($null -eq $items) { return NotEvaluated 'installations is not accessible.' }
    $count = 0
    foreach ($item in $items) {
        $value = Get-Prop $item 'repository_selection'
        if ($value -notin @('all', 'selected')) { return NotEvaluated 'repository_selection was not returned for an item.' }
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
    It 'org.apps-selected-repositories: Limit installed apps to selected repositories' {
        $result = if ($ComplianceContext) {
            $ComplianceContext.Result
        } else {
            Invoke-GHComplianceCheck -CheckId 'org.apps-selected-repositories' -Organization $env:GHE_ORGANIZATION -Repository $env:GHE_REPOSITORY `
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
