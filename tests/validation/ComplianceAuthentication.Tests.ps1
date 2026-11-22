BeforeAll {
    Import-Module "$PSScriptRoot/../../src/GitHubGovernance/GitHubGovernance.psd1" -Force
    $script:rsa = [System.Security.Cryptography.RSA]::Create(2048)
    $script:pem = $script:rsa.ExportRSAPrivateKeyPem()
}

AfterAll { $script:rsa.Dispose() }

Describe 'Governance command exports' {
    It 'exports every declared command under its new name' {
        $manifest = Test-ModuleManifest "$PSScriptRoot/../../src/GitHubGovernance/GitHubGovernance.psd1"
        $commands = @(Get-Command -Module GitHubGovernance | Select-Object -ExpandProperty Name)
        $commands.Count | Should -Be $manifest.ExportedFunctions.Count
        foreach ($name in $manifest.ExportedFunctions.Keys) {
            $commands | Should -Contain $name
        }
        foreach ($name in @('Connect-GHGovernance', 'Disconnect-GHGovernance', 'Get-GHOrganization',
                'Get-GHRepository', 'Get-GHEnterprisePolicy', 'Test-GHCompliance')) {
            $commands | Should -Contain $name
        }
        $commands | Should -Not -Contain 'Connect-GHEnterprise'
        $commands | Should -Not -Contain 'Get-GHERepository'
    }
}

Describe 'Compliance check authentication' {
    BeforeEach {
        $script:authorization = $null
        $script:installationPath = $null
        Mock Invoke-RestMethod -ModuleName GitHubGovernance {
            if ($Uri -like '*/installation') {
                if ($Uri -like '*/orgs/*') {
                    $script:installationPath = $Uri
                    $script:authorization = $Headers.Authorization
                }
                return [pscustomobject]@{ id = 42 }
            }
            if ($Uri -like '*/access_tokens') {
                return [pscustomobject]@{ token = 'fixture-token'; expires_at = [DateTimeOffset]::UtcNow.AddHours(1).ToString('o') }
            }
            if ($Uri -like '*/repos/*') {
                if ($Headers.Authorization -ne 'Bearer fixture-token') {
                    throw 'Incorrect installation token'
                }
                return [pscustomobject]@{ archived = $false; security_and_analysis = [pscustomobject]@{
                        secret_scanning = [pscustomobject]@{ status = 'enabled' }
                    }
                }
            }
            throw "Unexpected request: $Uri"
        }
    }

    AfterEach { Disconnect-GHGovernance }

    It 'requires an existing connection and rejects PAT connections' {
        { Invoke-GHComplianceCheck -CheckId 'repo.secret-scanning' -Organization 'org-a' -Repository 'repo-a' } |
            Should -Throw '*Connect-GHGovernance*'
        Connect-GHGovernance -Enterprise 'example' -Token 'fixture-token' | Out-Null
        { Invoke-GHComplianceCheck -CheckId 'repo.secret-scanning' -Organization 'org-a' -Repository 'repo-a' } |
            Should -Throw '*GitHub App connection*'
    }

    It 'uses the organization installation and a signed App JWT' {
        Connect-GHGovernance -Enterprise 'example' -AppClientId 'client' -AppPrivateKey $script:pem -ApiBaseUrl 'https://api.example.test' | Out-Null
        $result = Invoke-GHComplianceCheck -CheckId 'repo.secret-scanning' -Organization 'org-a' -Repository 'repo-a'
        $result.status | Should -Be 'pass'
        $script:installationPath | Should -Be 'https://api.example.test/orgs/org-a/installation'
        $jwt = $script:authorization.Substring('Bearer '.Length).Split('.')
        $signature = $jwt[2].Replace('-', '+').Replace('_', '/')
        $signature = [Convert]::FromBase64String($signature.PadRight($signature.Length + (4 - $signature.Length % 4) % 4, '='))
        $script:rsa.VerifyData([Text.Encoding]::UTF8.GetBytes("$($jwt[0]).$($jwt[1])"), $signature,
            [System.Security.Cryptography.HashAlgorithmName]::SHA256,
            [System.Security.Cryptography.RSASignaturePadding]::Pkcs1) | Should -BeTrue
    }

    It 'marks an inaccessible organization installation as not evaluated' {
        Connect-GHGovernance -Enterprise 'example' -AppClientId 'client' -AppPrivateKey $script:pem -ApiBaseUrl 'https://api.example.test' | Out-Null
        Mock Invoke-RestMethod -ModuleName GitHubGovernance {
            $response = [System.Net.Http.HttpResponseMessage]::new([System.Net.HttpStatusCode]::Forbidden)
            throw [Microsoft.PowerShell.Commands.HttpResponseException]::new('Forbidden', $response)
        }
        (Invoke-GHComplianceCheck -CheckId 'repo.secret-scanning' -Organization 'org-a' -Repository 'repo-a' -WarningAction SilentlyContinue).status | Should -Be 'na'
    }

    It 'surfaces unexpected API errors' {
        Connect-GHGovernance -Enterprise 'example' -AppClientId 'client' -AppPrivateKey $script:pem -ApiBaseUrl 'https://api.example.test' | Out-Null
        Mock Invoke-RestMethod -ModuleName GitHubGovernance { throw 'Connection failed' }
        { Invoke-GHComplianceCheck -CheckId 'repo.secret-scanning' -Organization 'org-a' -Repository 'repo-a' } |
            Should -Throw '*Connection failed*'
    }

    It 'surfaces repository request errors after an installation token was obtained' {
        Connect-GHGovernance -Enterprise 'example' -AppClientId 'client' -AppPrivateKey $script:pem -ApiBaseUrl 'https://api.example.test' | Out-Null
        (Invoke-GHComplianceCheck -CheckId 'repo.secret-scanning' -Organization 'org-a' -Repository 'repo-a').status | Should -Be 'pass'
        Mock Invoke-RestMethod -ModuleName GitHubGovernance { throw 'Repository request failed' }
        { Invoke-GHComplianceCheck -CheckId 'repo.secret-scanning' -Organization 'org-a' -Repository 'repo-a' } |
            Should -Throw '*Repository request failed*'
    }

    It 'rejects a malformed policy rather than silently skipping the check' {
        Connect-GHGovernance -Enterprise 'example' -AppClientId 'client' -AppPrivateKey $script:pem -ApiBaseUrl 'https://api.example.test' | Out-Null
        { Invoke-GHComplianceCheck -CheckId 'repo.secret-scanning' -Organization 'org-a' -Repository 'repo-a' -Config ([pscustomobject]@{}) } |
            Should -Throw '*boolean enabled value*'
    }

    It 'rejects insecure App endpoints without sending credentials' {
        { Connect-GHGovernance -Enterprise 'example' -AppClientId 'client' -AppPrivateKey $script:pem -ApiBaseUrl 'http://example.test' } |
            Should -Throw '*HTTPS*'
        Should -Invoke Invoke-RestMethod -ModuleName GitHubGovernance -Times 0
    }
}
