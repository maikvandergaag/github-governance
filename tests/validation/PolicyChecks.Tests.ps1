BeforeDiscovery {
    $cases = @(
        @{ id = 'enterprise.users-without-2fa'; kind = 'owner'; field = 'affiliatedUsersWithTwoFactorDisabledExist'; good = $false; bad = $true }
        @{ id = 'enterprise.sso-configured'; kind = 'ownerObject'; good = @{ samlIdentityProvider = @{ issuer = 'example' }; oidcProvider = $null }; bad = @{ samlIdentityProvider = $null; oidcProvider = $null } }
        @{ id = 'enterprise.default-permission-policy'; kind = 'owner'; field = 'defaultRepositoryPermissionSetting'; good = 'READ'; bad = 'ADMIN' }
        @{ id = 'enterprise.repo-creation-policy'; kind = 'ownerObject'; good = @{ membersCanCreateRepositoriesSetting = 'DISABLED'; membersCanCreatePublicRepositoriesSetting = $false }; bad = @{ membersCanCreateRepositoriesSetting = 'NO_POLICY'; membersCanCreatePublicRepositoriesSetting = $true } }
        @{ id = 'enterprise.repo-deletion-restricted'; kind = 'owner'; field = 'membersCanDeleteRepositoriesSetting'; good = 'DISABLED'; bad = 'ENABLED' }
        @{ id = 'enterprise.issue-deletion-restricted'; kind = 'owner'; field = 'membersCanDeleteIssuesSetting'; good = 'DISABLED'; bad = 'ENABLED' }
        @{ id = 'enterprise.visibility-change-restricted'; kind = 'owner'; field = 'membersCanChangeRepositoryVisibilitySetting'; good = 'DISABLED'; bad = 'ENABLED' }
        @{ id = 'enterprise.ip-allow-list'; kind = 'owner'; field = 'ipAllowListEnabledSetting'; good = 'ENABLED'; bad = 'DISABLED' }
        @{ id = 'enterprise.max-owners'; kind = 'owner'; field = 'admins'; good = @{ totalCount = 1; nodes = @(@{ login = 'one' }) }; bad = @{ totalCount = 4; nodes = @(@{ login = 'one' }) } }
        @{ id = 'enterprise.actions-restricted'; kind = 'actions'; good = 'selected'; bad = 'all' }
        @{ id = 'org.2fa-required'; kind = 'setting'; field = 'two_factor_requirement_enabled'; good = $true; bad = $false }
        @{ id = 'org.default-permission'; kind = 'setting'; field = 'default_repository_permission'; good = 'read'; bad = 'admin' }
        @{ id = 'org.no-public-repo-creation'; kind = 'setting'; field = 'members_can_create_public_repositories'; good = $false; bad = $true }
        @{ id = 'org.repo-creation-restricted'; kind = 'settingObject'; good = @{ members_can_create_public_repositories = $false; members_can_create_private_repositories = $false }; bad = @{ members_can_create_public_repositories = $false; members_can_create_private_repositories = $true } }
        @{ id = 'org.dependabot-alerts-new-repos'; kind = 'securityDefault'; field = 'dependabot_alerts'; good = 'enabled'; bad = 'disabled' }
        @{ id = 'org.secret-scanning-new-repos'; kind = 'securityDefault'; field = 'secret_scanning'; good = 'enabled'; bad = 'disabled' }
        @{ id = 'org.push-protection-new-repos'; kind = 'securityDefault'; field = 'secret_scanning_push_protection'; good = 'enabled'; bad = 'disabled' }
        @{ id = 'org.actions-restricted'; kind = 'actions'; good = 'selected'; bad = 'all' }
        @{ id = 'org.webhooks-tls'; kind = 'webhooks'; good = '0'; bad = '1' }
        @{ id = 'org.max-owners'; kind = 'admins'; good = 1; bad = 6 }
        @{ id = 'org.default-branch-ruleset'; kind = 'rulesets'; good = $true; bad = $false }
        @{ id = 'repo.not-public'; kind = 'repo'; good = @{ visibility = 'private'; archived = $false }; bad = @{ visibility = 'public'; archived = $false } }
        @{ id = 'repo.secret-scanning'; kind = 'repo'; good = @{ archived = $false; security_and_analysis = @{ secret_scanning = @{ status = 'enabled' } } }; bad = @{ archived = $false; security_and_analysis = @{ secret_scanning = @{ status = 'disabled' } } } }
        @{ id = 'repo.push-protection'; kind = 'repo'; good = @{ archived = $false; security_and_analysis = @{ secret_scanning_push_protection = @{ status = 'enabled' } } }; bad = @{ archived = $false; security_and_analysis = @{ secret_scanning_push_protection = @{ status = 'disabled' } } } }
        @{ id = 'repo.codeowners-present'; kind = 'ownersPresent'; good = $true; bad = $false }
        @{ id = 'repo.codeowners-valid'; kind = 'ownersValid'; good = $true; bad = $false }
        @{ id = 'repo.stale'; kind = 'stale'; good = 10; bad = 500 }
    )
}

BeforeAll {
    Import-Module "$PSScriptRoot/../../src/GitHubGovernance/GitHubGovernance.psd1" -Force
}

Describe 'Live policy checks' {
    BeforeEach {
        Mock Get-InstallationToken -ModuleName GitHubGovernance { 'fixture-token' }
        Connect-GHGovernance -Enterprise 'example' -AppClientId 'client' -AppPrivateKey 'unused' -ApiBaseUrl 'https://api.example.test' | Out-Null
    }

    AfterEach { Disconnect-GHGovernance }

    It '<id> evaluates live data and preserves unreadable results' -ForEach $cases {
        $config = Get-Content "$PSScriptRoot/../$id/policy.json" -Raw | ConvertFrom-Json
        $config.enabled = $true
        $script:case = $_
        Mock Invoke-GitHubGraphQL -ModuleName GitHubGovernance {
            if ($script:unavailable) {
                $response = [System.Net.Http.HttpResponseMessage]::new([System.Net.HttpStatusCode]::Forbidden)
                throw [Microsoft.PowerShell.Commands.HttpResponseException]::new('Forbidden', $response)
            }
            $item = $script:value
            switch ($script:case.kind) {
                { $_ -in 'owner', 'ownerObject' } {
                    $owner = if ($_ -eq 'owner') {
                        @{ $script:case.field = $item }
                    } else {
                        $item
                    }
                    $data = @{ enterprise = @{ ownerInfo = $owner } }
                }
                { $_ -in 'ownersPresent', 'ownersValid' } {
                    $present = $_ -eq 'ownersValid' -or $item
                    $data = @{ repository = @{ github = $(if ($present) {
                                    @{ text = '* @team' }
                                } else {
                                    $null
                                }); root = $null; docs = $null
                        }
                    }
                }
                default {
                    throw "Unexpected GraphQL fixture $($script:case.kind)"
                }
            }
            return (ConvertFrom-Json -InputObject (ConvertTo-Json -InputObject $data -Depth 20 -Compress))
        }
        Mock Invoke-GitHubRest -ModuleName GitHubGovernance {
            if ($script:unavailable) {
                return [pscustomobject]@{ Ok = $false; Status = 403; Data = $null }
            }
            $item = $script:value
            switch ($script:case.kind) {
                'actions' {
                    $data = @{ allowed_actions = $item }
                }
                'setting' {
                    $data = @{ $script:case.field = $item }
                }
                'settingObject' {
                    $data = $item
                }
                'securityDefault' {
                    $data = @(@{ default_for_new_repos = 'all'; configuration = @{ $script:case.field = $item } })
                }
                'webhooks' {
                    $data = @(@{ config = @{ insecure_ssl = $item; url = 'https://hooks.example' } })
                }
                'admins' {
                    $data = @(1..$item | ForEach-Object { @{ login = "owner$_" } })
                }
                'rulesets' {
                    if ($Path -match '/rulesets/1$') {
                        $data = @{ enforcement = 'active'; target = 'branch'; conditions = @{ ref_name = @{ include = @('~DEFAULT_BRANCH') } }; rules = @(@{ type = 'pull_request' }) }
                    } elseif ($item) {
                        $data = @(@{ id = 1 })
                    } else {
                        $data = @()
                    }
                }
                'repo' {
                    $data = $item
                }
                'stale' {
                    $data = @{ archived = $false; pushed_at = (Get-Date).AddDays(-$item).ToString('o') }
                }
                { $_ -in 'ownersPresent', 'ownersValid' } {
                    if ($Path -match '/codeowners/errors$') {
                        $data = if ($item) {
                            @{ errors = @() }
                        } else {
                            @{ errors = @(@{ line = 1; message = 'Unknown owner' }) }
                        }
                    } else {
                        $data = @{ archived = $false }
                    }
                }
                default {
                    throw "Unknown fixture type $($script:case.kind)"
                }
            }
            $json = ConvertTo-Json -InputObject $data -Depth 20 -Compress
            return [pscustomobject]@{ Ok = $true; Status = 200; Data = (ConvertFrom-Json -InputObject $json -NoEnumerate) }
        }
        $args = @{
            CheckId = $id; Organization = 'org-a'; Repository = 'repo-a'; Config = $config
        }
        $script:unavailable = $false
        $script:value = $good
        (Invoke-GHComplianceCheck @args).status | Should -Be 'pass'
        $script:value = $bad
        (Invoke-GHComplianceCheck @args).status | Should -Be 'fail'
        $script:unavailable = $true
        (Invoke-GHComplianceCheck @args).status | Should -Be 'na'
    }

    It 'evaluates repository creation conservatively for <label>' -ForEach @(
        @{ label = 'public creation enabled'; public = $true; private = $false; expected = 'fail' }
        @{ label = 'private creation missing'; public = $false; private = $null; expected = 'na' }
        @{ label = 'non-boolean setting'; public = 'false'; private = $false; expected = 'na' }
    ) {
        $script:settingsFixture = [pscustomobject]@{
            members_can_create_public_repositories = $public
            members_can_create_private_repositories = $private
        }
        Mock Invoke-GitHubRest -ModuleName GitHubGovernance {
            [pscustomobject]@{ Ok = $true; Status = 200; Data = $script:settingsFixture }
        }
        (Invoke-GHComplianceCheck -CheckId 'org.repo-creation-restricted' -Organization 'org-a').status | Should -Be $expected
    }
}
