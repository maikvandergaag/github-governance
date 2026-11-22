param($ComplianceContext, [switch] $PolicyOnly)

$PolicyCheck = {
    param($Repo, $Snap, $CodeOwners, $Params)
    if ($null -eq $Repo -or -not $Repo.PSObject.Properties['description']) {
        return NotEvaluated 'Repository description data is unavailable.'
    }
    $description = Get-Prop $Repo 'description'
    if ($null -ne $description -and $description -isnot [string]) {
        return NotEvaluated 'Repository description data is not a string.'
    }
    if ([string]::IsNullOrWhiteSpace($description)) {
        Fail 'The repository description is null, empty or whitespace-only.'
    } else {
        Pass
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
    It 'repo.description-present: Repository description is present' {
        $result = if ($ComplianceContext) {
            $ComplianceContext.Result
        } else {
            Invoke-GHComplianceCheck -CheckId 'repo.description-present' -Organization $env:GHE_ORGANIZATION -Repository $env:GHE_REPOSITORY `
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
