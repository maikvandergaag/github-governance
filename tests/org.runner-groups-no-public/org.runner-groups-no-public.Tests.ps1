param($ComplianceContext, [switch] $PolicyOnly)

$PolicyCheck = {
    param($Snap, $Params)
    $items = Get-Section $Snap 'runnerGroups'
    if ($null -eq $items) { return NotEvaluated 'runnerGroups is not accessible.' }
    $count = 0
    foreach ($item in $items) {
        $value = Get-Prop $item 'allows_public_repositories'
        if ($value -isnot [bool]) { return NotEvaluated 'allows_public_repositories was not returned for an item.' }
        if ($value -eq $true) { $count++ }
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
    It 'org.runner-groups-no-public: Restrict runner groups from public repositories' {
        $result = if ($ComplianceContext) {
            $ComplianceContext.Result
        } else {
            Invoke-GHComplianceCheck -CheckId 'org.runner-groups-no-public' -Organization $env:GHE_ORGANIZATION -Repository $env:GHE_REPOSITORY `
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
