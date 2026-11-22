BeforeAll {
    Import-Module "$PSScriptRoot/../../src/GitHubGovernance/GitHubGovernance.psd1" -Force
}

Describe 'Enterprise 2FA check' {
    BeforeEach {
        $script:setting = 'ENABLED'
        $script:graphErrors = @()
        Mock Get-InstallationToken -ModuleName GitHubGovernance { 'fixture-token' }
        Mock Invoke-RestMethod -ModuleName GitHubGovernance {
            [pscustomobject]@{
                data = [pscustomobject]@{ enterprise = [pscustomobject]@{
                        ownerInfo = [pscustomobject]@{ twoFactorRequiredSetting = $script:setting }
                    }
                }
                errors = $script:graphErrors
            }
        }
        Connect-GHGovernance -Enterprise 'example' -AppClientId 'client' -AppPrivateKey 'unused' | Out-Null
    }

    AfterEach { Disconnect-GHGovernance }

    It 'passes when 2FA is enabled' {
        (Invoke-GHComplianceCheck -CheckId 'enterprise.2fa-required').status | Should -Be 'pass'
    }

    It 'fails when the enterprise has no enforced policy' {
        $script:setting = 'NO_POLICY'
        $result = Invoke-GHComplianceCheck -CheckId 'enterprise.2fa-required'
        $result.status | Should -Be 'fail'
        $result.detail | Should -Match 'not enforced'
    }

    It 'does not evaluate a missing or inaccessible setting' {
        $script:setting = $null
        (Invoke-GHComplianceCheck -CheckId 'enterprise.2fa-required').status | Should -Be 'na'
        $script:setting = 'ENABLED'
        $script:graphErrors = @([pscustomobject]@{ message = 'Forbidden'; path = @('enterprise', 'ownerInfo', 'twoFactorRequiredSetting') })
        (Invoke-GHComplianceCheck -CheckId 'enterprise.2fa-required').status | Should -Be 'na'
    }

    It 'surfaces unexpected GraphQL errors' {
        Mock Invoke-RestMethod -ModuleName GitHubGovernance { throw 'Connection failed' }
        { Invoke-GHComplianceCheck -CheckId 'enterprise.2fa-required' } | Should -Throw '*Connection failed*'
    }

    It 'marks an inaccessible GraphQL setting as not evaluated' {
        Mock Invoke-RestMethod -ModuleName GitHubGovernance {
            $response = [System.Net.Http.HttpResponseMessage]::new([System.Net.HttpStatusCode]::Forbidden)
            throw [Microsoft.PowerShell.Commands.HttpResponseException]::new('Forbidden', $response)
        }
        $result = Invoke-GHComplianceCheck -CheckId 'enterprise.2fa-required'
        $result.status | Should -Be 'na'
        $result.detail | Should -Match '403'
    }
}
