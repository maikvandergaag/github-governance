param($ComplianceContext, [switch] $PolicyOnly)

$PolicyCheck = {
    param($Repo, $Snap, $CodeOwners, $Params)
    if ($null -eq $CodeOwners -or -not (Get-Prop $CodeOwners 'pathEvaluated')) {
        return NotEvaluated 'CODEOWNERS location was not fully evaluated.'
    }
    if (-not $CodeOwners.path) {
        return NotEvaluated 'No CODEOWNERS file to validate.'
    }
    if (-not (Get-Prop $CodeOwners 'errorsEvaluated')) {
        return NotEvaluated 'CODEOWNERS validation was not fully evaluated.'
    }
    $errors = @(@(Get-Prop $CodeOwners 'errors') | Where-Object { $_ })
    if ($errors.Count -eq 0) {
        Pass
    } else {
        Fail (($errors | ForEach-Object { "line $(Get-Prop $_ 'line'): $(Get-Prop $_ 'message')" }) -join '; ')
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
    It 'repo.codeowners-valid: CODEOWNERS file has no errors' {
        $result = if ($ComplianceContext) {
            $ComplianceContext.Result
        } else {
            Invoke-GHComplianceCheck -CheckId 'repo.codeowners-valid' -Organization $env:GHE_ORGANIZATION -Repository $env:GHE_REPOSITORY `
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
