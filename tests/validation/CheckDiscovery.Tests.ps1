BeforeAll {
    Import-Module "$PSScriptRoot/../../src/GitHubGovernance/GitHubGovernance.psd1" -Force
}

Describe 'Compliance check discovery' {
    It 'runs a new manifested check without adding it to a registry or central policy' {
        $testsPath = Join-Path $TestDrive 'tests'
        $checkPath = Join-Path $testsPath 'org.example-check'
        $dataPath = Join-Path $TestDrive 'data'
        New-Item -ItemType Directory -Path $checkPath, (Join-Path $dataPath 'organizations') -Force | Out-Null

        @{
            id = 'org.example-check'
            scope = 'org'
            title = 'Example check'
            remediation = 'Apply the required organization setting.'
            dataSource = @{ type = 'organization-section'; section = 'settings' }
        } | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $checkPath 'check.json')
        @{ enabled = $true; severity = 'low' } | ConvertTo-Json | Set-Content (Join-Path $checkPath 'policy.json')
        'Example issue template.' | Set-Content (Join-Path $checkPath 'issue.md')
        @'
param($ComplianceContext, [switch] $PolicyOnly)
$PolicyCheck = { param($Snap, $Params) Fail 'Example finding.' }
if ($PolicyOnly) { return $PolicyCheck }
'@ | Set-Content (Join-Path $checkPath 'org.example-check.Tests.ps1')

        @{ checks = @{}; exemptions = @{} } |
            ConvertTo-Json -Depth 5 |
            Set-Content (Join-Path $TestDrive 'compliance-policy.json')
        @{ login = 'org-a'; repositories = @{ Ok = $true; Data = @() } } |
            ConvertTo-Json -Depth 5 |
            Set-Content (Join-Path $dataPath 'organizations/org-a.json')

        $result = @(Test-GHCompliance -DataPath $dataPath `
                -PolicyPath (Join-Path $TestDrive 'compliance-policy.json') `
                -TestsPath $testsPath) |
            Where-Object id -eq 'org-a'

        $result.failures.Count | Should -Be 1
        $result.failures[0].check | Should -Be 'org.example-check'
        $result.failures[0].title | Should -Be 'Example check'
        $result.failures[0].severity | Should -Be 'low'
        $result.failures[0].remediation | Should -Be 'Apply the required organization setting.'
    }
}
