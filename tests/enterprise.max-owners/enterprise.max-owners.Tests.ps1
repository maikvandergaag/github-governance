param($ComplianceContext, [switch] $PolicyOnly)

$PolicyCheck = {
    param($Snap, $Params)
    $f = Get-OwnerInfoField $Snap 'admins'
    $count = Get-Prop $f.Value 'totalCount'
    if (-not $f.Readable -or $null -eq $count) {
        return NotEvaluated 'Enterprise owners not readable.'
    }
    if ($count -le [int]$Params.max) {
        Pass
    } else {
        Fail "$count enterprise owners (max $($Params.max)): $((@(Get-Prop $f.Value 'nodes') | Where-Object { $_ } | ForEach-Object login | Sort-Object) -join ', ')"
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

Describe 'GitHub compliance' -Tag 'compliance', 'enterprise' {
    It 'enterprise.max-owners: Number of enterprise owners is limited' {
        $result = if ($ComplianceContext) {
            $ComplianceContext.Result
        } else {
            Invoke-GHComplianceCheck -CheckId 'enterprise.max-owners' -Organization $env:GHE_ORGANIZATION -Repository $env:GHE_REPOSITORY `
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
