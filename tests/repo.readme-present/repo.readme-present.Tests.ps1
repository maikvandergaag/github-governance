param($ComplianceContext, [switch] $PolicyOnly)

$PolicyCheck = {
    param($Repo, $Snap, $CodeOwners, $Params)
    $evidence = Get-Prop $Repo 'complianceReadme'
    if ((Get-Prop $evidence 'evaluated') -cne $true -or (Get-Prop $evidence 'present') -isnot [bool]) {
        return NotEvaluated 'Root README.md presence on the default branch could not be evaluated.'
    }
    if ($evidence.present) {
        Pass
    } else {
        Fail 'No regular README.md file at the repository root on the default branch.'
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

Describe 'GitHub compliance' -Tag 'compliance', 'repo' {
    It 'repo.readme-present: Root README.md file is present' {
        $result = if ($ComplianceContext) {
            $ComplianceContext.Result
        } else {
            Invoke-GHComplianceCheck -CheckId 'repo.readme-present' -Organization $env:GHE_ORGANIZATION -Repository $env:GHE_REPOSITORY `
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
