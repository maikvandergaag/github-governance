BeforeAll {
    Import-Module "$PSScriptRoot/../../src/GitHubGovernance/GitHubGovernance.psd1" -Force
    $script:rsa = [System.Security.Cryptography.RSA]::Create(2048)
    $script:pem = $script:rsa.ExportRSAPrivateKeyPem()
}

AfterAll { $script:rsa.Dispose() }

Describe 'Standalone account support' {
    BeforeEach {
        $script:uris = [System.Collections.Generic.List[string]]::new()
        $script:selection = 'all'
        $script:checks = @{}
        foreach ($directory in Get-ChildItem "$PSScriptRoot/../*" -Directory) {
            $manifestPath = Join-Path $directory.FullName 'check.json'
            if (Test-Path -LiteralPath $manifestPath) {
                $id = (Get-Content $manifestPath -Raw | ConvertFrom-Json).id
                $script:checks[$id] = @{ enabled = $false }
            }
        }
        Mock Invoke-RestMethod -ModuleName GitHubGovernance {
            $script:uris.Add($Uri)
            if ($Uri -like '*/installation') {
                return [pscustomobject]@{ id = 1; repository_selection = $script:selection }
            }
            if ($Uri -like '*/access_tokens') {
                return [pscustomobject]@{ token = 'fixture'; expires_at = [DateTimeOffset]::UtcNow.AddHours(1).ToString('o') }
            }
            if ($Uri -like '*/graphql') {
                $files = [pscustomobject]@{ github = $null; root = $null; docs = $null }
                return [pscustomobject]@{ data = [pscustomobject]@{ r0 = $files; repository = $files } }
            }
            if ($Uri -like '*/installation/repositories?*') {
                return [pscustomobject]@{ repositories = @(
                        [pscustomobject]@{ name = 'owned'; owner = [pscustomobject]@{ login = 'alice' } }
                        [pscustomobject]@{ name = 'other'; owner = [pscustomobject]@{ login = 'another' } }
                    ) }
            }
            if ($Uri -like '*/repos/alice/owned') {
                return [pscustomobject]@{ name = 'owned'; archived = $false; visibility = 'public'; default_branch = 'main' }
            }
            if ($Uri -like '*/orgs/example/repos?*') {
                return @([pscustomobject]@{ name = 'owned'; archived = $false; visibility = 'public'; default_branch = 'main' })
            }
            if ($Uri -like '*/orgs/example') {
                return [pscustomobject]@{ two_factor_requirement_enabled = $false }
            }
            if ($Uri -like '*/repos/example/owned') {
                return [pscustomobject]@{ name = 'owned'; archived = $false; visibility = 'public'; default_branch = 'main' }
            }
            throw "Unexpected request: $Uri"
        }
    }

    AfterEach { Disconnect-GHGovernance }

    It 'uses the personal installation and evaluates only owned repositories' {
        Connect-GHGovernance -User alice -AppClientId 'client' -AppPrivateKey $script:pem -ApiBaseUrl 'https://api.example.test' | Out-Null
        $output = Join-Path $TestDrive 'personal'
        Export-GHDocumentation -OutputPath $output
        $script:checks['repo.not-public'] = @{ enabled = $true; severity = 'high' }
        $script:checks['repo.codeowners-present'] = @{ enabled = $true; severity = 'medium' }
        $script:checks['org.2fa-required'] = @{ enabled = $true }
        $policy = @{ checks = $script:checks; exemptions = @{} }
        $policyPath = Join-Path $TestDrive 'policy.json'
        $policy | ConvertTo-Json -Depth 10 | Set-Content $policyPath
        $results = @(Test-GHCompliance -DataPath "$output/_data" -PolicyPath $policyPath -UsePester)
        $script:uris | Should -Contain 'https://api.example.test/users/alice/installation'
        $script:uris | Should -Contain 'https://api.example.test/repos/alice/owned'
        @($results | Where-Object type -eq 'enterprise').Count | Should -Be 0
        @($results | Where-Object type -eq 'org').Count | Should -Be 0
        ($results | Where-Object id -eq 'alice').type | Should -Be 'account'
        @($results | Where-Object type -eq 'repo').Count | Should -Be 1
        @(($results | Where-Object id -eq 'alice/owned').failures.check) | Should -Contain 'repo.not-public'
        @(($results | Where-Object id -eq 'alice/owned').failures.check) | Should -Contain 'repo.codeowners-present'
        Test-Path "$output/organizations/alice/repositories.md" | Should -BeTrue
        Test-Path "$output/organizations/alice/codeowners.md" | Should -BeTrue
        Get-Content "$output/organizations/alice/README.md" -Raw | Should -Match '\[Configuration handbook\]'
        { Invoke-GHComplianceCheck -CheckId 'org.2fa-required' -Organization alice } | Should -Throw '*do not apply to a personal account*'
        { Invoke-GHComplianceCheck -CheckId 'enterprise.2fa-required' } | Should -Throw '*require an enterprise connection*'
    }

    It 'routes standalone organization authentication to its installation' {
        Connect-GHGovernance -Organization example -AppClientId 'client' -AppPrivateKey $script:pem -ApiBaseUrl 'https://api.example.test' | Out-Null
        $script:uris | Should -Contain 'https://api.example.test/orgs/example/installation'
    }

    It 'exports an organization and evaluates its organization and repository checks' {
        Mock Get-OrgSection -ModuleName GitHubGovernance {
            [pscustomobject]@{ Ok = $true; Status = 200; Data = @() }
        }
        Connect-GHGovernance -Organization example -AppClientId 'client' -AppPrivateKey $script:pem -ApiBaseUrl 'https://api.example.test' | Out-Null
        $output = Join-Path $TestDrive 'organization'
        Export-GHDocumentation -OutputPath $output -SkipCodeOwners
        $script:checks['org.2fa-required'] = @{ enabled = $true; severity = 'high' }
        $script:checks['repo.not-public'] = @{ enabled = $true; severity = 'high' }
        $script:checks['enterprise.2fa-required'] = @{ enabled = $true; severity = 'high' }
        $policy = @{ checks = $script:checks; exemptions = @{} }
        $policyPath = Join-Path $TestDrive 'org-policy.json'
        $policy | ConvertTo-Json -Depth 10 | Set-Content $policyPath
        $results = @(Test-GHCompliance -DataPath "$output/_data" -PolicyPath $policyPath -UsePester)
        @($results | Where-Object type -eq 'enterprise').Count | Should -Be 0
        @($results | Where-Object type -eq 'org').Count | Should -Be 1
        @($results | Where-Object type -eq 'repo').Count | Should -Be 1
        @(($results | Where-Object id -eq 'example').failures.check) | Should -Contain 'org.2fa-required'
        @(($results | Where-Object id -eq 'example/owned').failures.check) | Should -Contain 'repo.not-public'
        { Invoke-GHComplianceCheck -CheckId 'enterprise.2fa-required' } | Should -Throw '*require an enterprise connection*'
    }

    It 'rejects selected-repository installations' {
        $script:selection = 'selected'
        { Connect-GHGovernance -User alice -AppClientId 'client' -AppPrivateKey $script:pem } | Should -Throw '*all repositories*'
        { Get-GHConnection } | Should -Throw '*Not connected*'
    }

    It 'rejects a stale snapshot for another account' {
        Connect-GHGovernance -User alice -AppClientId 'client' -AppPrivateKey $script:pem | Out-Null
        $path = Join-Path $TestDrive 'data'
        New-Item -ItemType Directory -Path "$path/organizations" -Force | Out-Null
        '{"login":"bob","accountType":"user"}' | Set-Content "$path/organizations/bob.json"
        { Test-GHCompliance -DataPath $path -UsePester } | Should -Throw '*does not match the connected account*'
    }
}
