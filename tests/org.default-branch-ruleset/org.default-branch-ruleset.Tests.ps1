param($ComplianceContext, [switch] $PolicyOnly)

$PolicyCheck = {
    param($Snap, $Params)
    $rulesets = Get-Section $Snap 'rulesets'
    if ($null -eq $rulesets) {
        return NotEvaluated 'Rulesets not available.'
    }
    if ($rulesets.Count -gt 0 -and (Get-Prop $Snap 'rulesetDetailsComplete') -ne $true) {
        return NotEvaluated 'Organization ruleset details were not fully evaluated.'
    }
    $match = @(@(Get-Prop $Snap 'rulesetDetails') | Where-Object {
            $_ -and (Get-Prop $_ 'enforcement') -eq 'active' -and (Get-Prop $_ 'target') -eq 'branch' -and
            (@(Get-Prop $_ 'conditions.ref_name.include') | Where-Object { $_ -in '~DEFAULT_BRANCH', '~ALL' }) -and
            (@(Get-Prop $_ 'rules') | Where-Object { $_ -and $_.type -eq 'pull_request' })
        })
    if ($match.Count -gt 0) {
        Pass
    } else {
        Fail 'No active branch ruleset on ~DEFAULT_BRANCH/~ALL with a pull_request rule.'
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
    It 'org.default-branch-ruleset: An active ruleset requires pull requests on default branches' {
        $result = if ($ComplianceContext) {
            $ComplianceContext.Result
        } else {
            Invoke-GHComplianceCheck -CheckId 'org.default-branch-ruleset' -Organization $env:GHE_ORGANIZATION -Repository $env:GHE_REPOSITORY `
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
