param($ComplianceContext, [switch] $PolicyOnly)

$PolicyCheck = {
    param($Snap, $Params)
    $setting = Get-OwnerInfoField $Snap 'membersCanCreateRepositoriesSetting'
    if (-not $setting.Readable) {
        return NotEvaluated 'membersCanCreateRepositoriesSetting not readable.'
    }
    if ($null -eq $setting.Value) {
        return NotEvaluated 'Repository creation setting was not returned.'
    }
    if ($setting.Value -eq 'NO_POLICY') {
        return Fail 'Repository creation is not enforced at enterprise level (organizations decide).'
    }
    $public = Get-OwnerInfoField $Snap 'membersCanCreatePublicRepositoriesSetting'
    if (-not $public.Readable -or $null -eq $public.Value) {
        return NotEvaluated 'Public repository creation setting is not readable.'
    }
    if ($public.Readable -and $public.Value -eq $true) {
        return Fail 'Members can create public repositories.'
    }
    Pass
}

if ($PolicyOnly) {
    return $PolicyCheck
}

BeforeAll {
    if (-not $ComplianceContext -and -not (Get-Module GitHubGovernance)) {
        throw 'Import the GitHubGovernance module and connect a GitHub App before running compliance tests.'
    }
}

Describe 'GitHub compliance' -Tag 'compliance', 'enterprise' {
    It 'enterprise.repo-creation-policy: Repository creation is restricted at enterprise level' {
        $result = if ($ComplianceContext) {
            $ComplianceContext.Result
        } else {
            Invoke-GHComplianceCheck -CheckId 'enterprise.repo-creation-policy' -Organization $env:GHE_ORGANIZATION -Repository $env:GHE_REPOSITORY `
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
