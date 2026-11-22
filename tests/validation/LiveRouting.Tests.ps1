BeforeAll {
    Import-Module "$PSScriptRoot/../../src/GitHubGovernance/GitHubGovernance.psd1" -Force
    $script:rsa = [System.Security.Cryptography.RSA]::Create(2048)
    $script:pem = $script:rsa.ExportRSAPrivateKeyPem()
}

AfterAll {
    $script:rsa.Dispose()
}

Describe 'Live request routing' {
    BeforeEach {
        $script:uris = [System.Collections.Generic.List[string]]::new()
        $script:queryBody = $null
        Mock Invoke-RestMethod -ModuleName GitHubGovernance {
            $script:uris.Add($Uri)
            if ($Uri -like '*/installation') {
                return [pscustomobject]@{ id = 42 }
            }
            if ($Uri -like '*/access_tokens') {
                return [pscustomobject]@{ token = 'fixture-token'; expires_at = [DateTimeOffset]::UtcNow.AddHours(1).ToString('o') }
            }
            if ($Uri -like '*/graphql') {
                $script:queryBody = $Body | ConvertFrom-Json
                return [pscustomobject]@{ data = [pscustomobject]@{ enterprise = [pscustomobject]@{
                            ownerInfo = [pscustomobject]@{ admins = [pscustomobject]@{ totalCount = 1; nodes = @() } }
                        }
                    }
                }
            }
            if ($Uri -like '*/orgs/org-a') {
                return [pscustomobject]@{ two_factor_requirement_enabled = $true }
            }
            throw "Unexpected request: $Uri"
        }
        Connect-GHGovernance -Enterprise 'example' -AppClientId 'client' -AppPrivateKey $script:pem -ApiBaseUrl 'https://api.example.test' | Out-Null
    }

    AfterEach { Disconnect-GHGovernance }

    It 'queries enterprise policy with the enterprise installation' {
        $result = Invoke-GHComplianceCheck -CheckId 'enterprise.max-owners'
        $result.status | Should -Be 'pass'
        $script:uris | Should -Contain 'https://api.example.test/enterprises/example/installation'
        $script:queryBody.variables.slug | Should -Be 'example'
        $script:queryBody.query | Should -Match 'admins'
    }

    It 'queries organization settings with the organization installation' {
        $result = Invoke-GHComplianceCheck -CheckId 'org.2fa-required' -Organization 'org-a'
        $result.status | Should -Be 'pass'
        $script:uris | Should -Contain 'https://api.example.test/orgs/org-a/installation'
        $script:uris | Should -Contain 'https://api.example.test/orgs/org-a'
    }
}
