BeforeAll {
    Import-Module "$PSScriptRoot/../../src/GitHubGovernance/GitHubGovernance.psd1" -Force
}

Describe 'Incomplete live data' {
    BeforeEach {
        Mock Get-InstallationToken -ModuleName GitHubGovernance { 'fixture-token' }
        Connect-GHGovernance -Enterprise 'example' -AppClientId 'client' -AppPrivateKey 'unused' -ApiBaseUrl 'https://api.example.test' | Out-Null
    }

    AfterEach { Disconnect-GHGovernance }

    It 'evaluates repository descriptions in live and snapshot data: <label>' -TestCases @(
        @{ label = 'present'; data = @{ description = 'Project API' }; expected = 'pass' }
        @{ label = 'null'; data = @{ description = $null }; expected = 'fail' }
        @{ label = 'empty'; data = @{ description = '' }; expected = 'fail' }
        @{ label = 'whitespace'; data = @{ description = " `t`r`n" }; expected = 'fail' }
        @{ label = 'missing field'; data = @{}; expected = 'na' }
        @{ label = 'invalid type'; data = @{ description = 123 }; expected = 'na' }
    ) {
        param($data, $expected)
        $script:descriptionRepository = [pscustomobject]$data
        Mock Invoke-GitHubRest -ModuleName GitHubGovernance {
            [pscustomobject]@{ Ok = $true; Status = 200; Data = $script:descriptionRepository }
        }
        (Invoke-GHComplianceCheck -CheckId 'repo.description-present' -Organization 'org-a' -Repository 'repo-a').status | Should -Be $expected
        Should -Invoke Invoke-GitHubRest -ModuleName GitHubGovernance -Times 1 -Exactly -ParameterFilter {
            $Path -eq 'repos/org-a/repo-a' -and $StrictErrors
        }
        $snapshotResult = & (Get-Module GitHubGovernance) {
            param($path, $repository)
            $check = & $path -PolicyOnly
            & $check $repository $null $null $null
        } "$PSScriptRoot/../repo.description-present/repo.description-present.Tests.ps1" $script:descriptionRepository
        $snapshotResult.status | Should -Be $expected
    }

    It 'does not evaluate descriptions in inaccessible or archived repositories: <label>' -TestCases @(
        @{ label = 'inaccessible'; ok = $false; status = 403; archived = $false }
        @{ label = 'archived'; ok = $true; status = 200; archived = $true }
    ) {
        param($ok, $status, $archived)
        $script:descriptionResponse = [pscustomobject]@{
            Ok = $ok; Status = $status; Data = [pscustomobject]@{ archived = $archived; description = $null }
        }
        Mock Invoke-GitHubRest -ModuleName GitHubGovernance { $script:descriptionResponse }
        (Invoke-GHComplianceCheck -CheckId 'repo.description-present' -Organization 'org-a' -Repository 'repo-a').status | Should -Be 'na'
    }

    It '<id> distinguishes disabled Actions from an unavailable policy' -TestCases @(
        @{ id = 'enterprise.actions-restricted'; disabledProperty = 'enabled_organizations' }
        @{ id = 'org.actions-restricted'; disabledProperty = 'enabled_repositories' }
    ) {
        Mock Invoke-GitHubRest -ModuleName GitHubGovernance {
            [pscustomobject]@{ Ok = $true; Status = 200; Data = $script:actionsResponse }
        }
        $script:actionsResponse = [pscustomobject]@{}
        (Invoke-GHComplianceCheck -CheckId $id -Organization 'org-a').status | Should -Be 'na'
        $script:actionsResponse = [pscustomobject]@{ $disabledProperty = 'none' }
        (Invoke-GHComplianceCheck -CheckId $id -Organization 'org-a').status | Should -Be 'pass'
    }

    It 'does not treat a missing public creation setting as compliant' {
        Mock Invoke-GitHubGraphQL -ModuleName GitHubGovernance {
            [pscustomobject]@{ enterprise = [pscustomobject]@{ ownerInfo = [pscustomobject]@{
                        membersCanCreateRepositoriesSetting = 'DISABLED'; membersCanCreatePublicRepositoriesSetting = $null
                    }
                }
            }
        }
        (Invoke-GHComplianceCheck -CheckId 'enterprise.repo-creation-policy').status | Should -Be 'na'
    }

    It 'does not treat missing repository visibility as compliant' {
        Mock Invoke-GitHubRest -ModuleName GitHubGovernance {
            [pscustomobject]@{ Ok = $true; Status = 200; Data = [pscustomobject]@{ archived = $false } }
        }
        (Invoke-GHComplianceCheck -CheckId 'repo.not-public' -Organization 'org-a' -Repository 'repo-a').status | Should -Be 'na'
    }

    It 'checks CODEOWNERS presence without requiring access to validation errors' {
        Mock Invoke-GitHubRest -ModuleName GitHubGovernance {
            if ($Path -like '*/codeowners/errors') {
                throw 'Validation endpoint should not be called.'
            }
            [pscustomobject]@{ Ok = $true; Status = 200; Data = [pscustomobject]@{ archived = $false } }
        }
        Mock Invoke-GitHubGraphQL -ModuleName GitHubGovernance {
            [pscustomobject]@{ repository = [pscustomobject]@{
                    github = [pscustomobject]@{ text = '* @team' }; root = $null; docs = $null
                }
            }
        }
        (Invoke-GHComplianceCheck -CheckId 'repo.codeowners-present' -Organization 'org-a' -Repository 'repo-a').status | Should -Be 'pass'
        Should -Invoke Invoke-GitHubRest -ModuleName GitHubGovernance -ParameterFilter { $Path -like '*/codeowners/errors' } -Times 0
    }

    It 'does not treat a missing CODEOWNERS errors list as successful validation' {
        Mock Invoke-GitHubRest -ModuleName GitHubGovernance {
            [pscustomobject]@{ Ok = $true; Status = 200; Data = [pscustomobject]@{} }
        }
        Mock Invoke-GitHubGraphQL -ModuleName GitHubGovernance {
            [pscustomobject]@{ repository = [pscustomobject]@{
                    github = [pscustomobject]@{ text = '* @team' }; root = $null; docs = $null
                }
            }
        }
        (Invoke-GHComplianceCheck -CheckId 'repo.codeowners-valid' -Organization 'org-a' -Repository 'repo-a').status | Should -Be 'na'
    }
}
