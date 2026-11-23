Describe 'Compliance JSON schema validation' {
    BeforeAll {
        Import-Module "$PSScriptRoot/../../src/GitHubGovernance/GitHubGovernance.psd1" -Force

        function Invoke-ComplianceSchemaFixture {
            param($Policy)
            $checkId = 'org.example-check'
            $checkPath = Join-Path $script:testsPath $checkId
            New-Item -ItemType Directory -Path $checkPath, (Join-Path $script:dataPath 'organizations') -Force | Out-Null
            $script:manifest | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $checkPath 'check.json')
            $script:localPolicy | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $checkPath 'policy.json')
            'Example issue template.' | Set-Content (Join-Path $checkPath 'issue.md')
            @'
param($ComplianceContext, [switch] $PolicyOnly)
$PolicyCheck = { param($Snap, $Params) @{ status = 'pass' } }
if ($PolicyOnly) { return $PolicyCheck }
'@ | Set-Content (Join-Path $checkPath "$checkId.Tests.ps1")
            $Policy | ConvertTo-Json -Depth 10 | Set-Content $script:policyPath
            Test-GHCompliance -DataPath $script:dataPath -PolicyPath $script:policyPath -TestsPath $script:testsPath | Out-Null
        }
    }

    BeforeEach {
        $script:testsPath = Join-Path $TestDrive 'tests'
        $script:dataPath = Join-Path $TestDrive 'data'
        $script:policyPath = Join-Path $TestDrive 'compliance-policy.json'
        $script:manifest = [ordered]@{
            id = 'org.example-check'
            scope = 'org'
            title = 'Example check'
            remediation = 'Apply the required organization setting.'
            dataSource = @{ type = 'organization-section'; section = 'settings' }
            parameters = @{
                type = 'object'
                properties = @{ days = @{ type = 'integer'; minimum = 1 } }
                required = @('days')
                additionalProperties = $false
            }
        }
        $script:localPolicy = @{ enabled = $true; severity = 'low'; params = @{ days = 30 } }
        $script:centralPolicy = @{ checks = @{}; exemptions = @{} }
    }

    It 'accepts a valid manifest and merged policy before evaluation' {
        $script:centralPolicy.checks['org.example-check'] = @{ params = @{ days = 60 } }
        { Invoke-ComplianceSchemaFixture $script:centralPolicy } | Should -Not -Throw
    }

    It 'rejects unknown manifest properties' {
        $script:manifest.unexpected = $true
        { Invoke-ComplianceSchemaFixture $script:centralPolicy } | Should -Throw '*unexpected is not allowed*'
    }

    It 'rejects invalid local parameter types' {
        $script:localPolicy.params.days = '30'
        { Invoke-ComplianceSchemaFixture $script:centralPolicy } | Should -Throw '*must be of type integer*'
    }

    It 'rejects invalid local severity values' {
        $script:localPolicy.severity = 'urgent'
        { Invoke-ComplianceSchemaFixture $script:centralPolicy } | Should -Throw '*severity*'
    }

    It 'rejects invalid central severity values' {
        $script:centralPolicy.checks['org.example-check'] = @{ severity = 'urgent' }
        { Invoke-ComplianceSchemaFixture $script:centralPolicy } | Should -Throw '*severity*'
    }

    It 'rejects undeclared central parameters' {
        $script:centralPolicy.checks['org.example-check'] = @{ params = @{ days = 60; unknown = $true } }
        { Invoke-ComplianceSchemaFixture $script:centralPolicy } | Should -Throw '*unknown is not allowed*'
    }

    It 'rejects exemptions for unknown checks and mismatched target scopes' {
        $script:centralPolicy.exemptions['org-a'] = @('org.missing-check')
        { Invoke-ComplianceSchemaFixture $script:centralPolicy } | Should -Throw '*unknown check*'

        $script:centralPolicy.exemptions = @{ 'enterprise:example' = @('org.example-check') }
        { Invoke-ComplianceSchemaFixture $script:centralPolicy } | Should -Throw '*cannot reference org check*'
    }
}
