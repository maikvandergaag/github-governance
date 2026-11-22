BeforeAll {
    Import-Module "$PSScriptRoot/../../src/GitHubGovernance/GitHubGovernance.psd1" -Force
}

Describe 'Snapshot compliance uses shared policy logic' {
    BeforeEach {
        $dataPath = Join-Path $TestDrive 'data'
        New-Item -ItemType Directory -Path (Join-Path $dataPath 'organizations') -Force | Out-Null
        $script:enterprise = @{
            slug = 'example'
            graph = @{
                Ok = $true; ErrorPaths = @()
                Data = @{ ownerInfo = @{
                        twoFactorRequiredSetting = 'ENABLED'
                        membersCanCreateRepositoriesSetting = 'DISABLED'
                        membersCanCreatePublicRepositoriesSetting = $null
                    }
                }
            }

            actionsPermissions = @{ Ok = $true; Data = @{} }
        }
        $script:organization = @{
            login = 'org-a'
            actionsPermissions = @{ Ok = $true; Data = @{} }
            repositories = @{ Ok = $true; Data = @(@{ name = 'repo-a'; archived = $false }) }
            codeOwners = $null
        }
        $checks = @{}
        foreach ($directory in Get-ChildItem "$PSScriptRoot/../*" -Directory) {
            $manifestPath = Join-Path $directory.FullName 'check.json'
            if (Test-Path -LiteralPath $manifestPath) {
                $id = (Get-Content $manifestPath -Raw | ConvertFrom-Json).id
                $checks[$id] = @{ enabled = $false; severity = 'medium' }
            }
        }
        $checks['enterprise.2fa-required'] = @{ enabled = $true; severity = 'high' }
        $checks['enterprise.repo-creation-policy'] = @{ enabled = $true; severity = 'high' }
        $checks['enterprise.actions-restricted'] = @{ enabled = $true; severity = 'high'; params = @{ allowed = @('selected') } }
        $checks['org.actions-restricted'] = @{ enabled = $true; severity = 'high'; params = @{ allowed = @('selected') } }
        $checks['repo.not-public'] = @{ enabled = $true; severity = 'high' }
        $policy = @{
            checks = $checks
            exemptions = @{}
        }
        $script:policyPath = Join-Path $TestDrive 'policy.json'
        $policy | ConvertTo-Json -Depth 20 | Set-Content $script:policyPath
    }

    It 'does not report missing settings as compliant or failed' {
        $script:enterprise | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $dataPath 'enterprise.json')
        $script:organization | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $dataPath 'organizations/org-a.json')
        $results = @(Test-GHCompliance -DataPath $dataPath -PolicyPath $script:policyPath)
        $enterprise = $results | Where-Object id -eq 'enterprise:example'
        $org = $results | Where-Object id -eq 'org-a'
        $repo = $results | Where-Object id -eq 'org-a/repo-a'

        @($enterprise.notEvaluated.check) | Should -Contain 'enterprise.repo-creation-policy'
        @($enterprise.notEvaluated.check) | Should -Contain 'enterprise.actions-restricted'
        @($org.notEvaluated.check) | Should -Contain 'org.actions-restricted'
        @($repo.notEvaluated.check) | Should -Contain 'repo.not-public'
        @($results | Where-Object { @($_.failures).Count -gt 0 }).Count | Should -Be 0
    }

    It 'uses the same 2FA decision for snapshots and live evaluation' -TestCases @(
        @{ setting = 'ENABLED'; expected = 'pass' }
        @{ setting = 'NO_POLICY'; expected = 'fail' }
        @{ setting = $null; expected = 'na' }
    ) {
        $script:enterprise.graph.Data.ownerInfo.twoFactorRequiredSetting = $setting
        $script:enterprise | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $dataPath 'enterprise.json')
        $script:organization | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $dataPath 'organizations/org-a.json')
        Mock Get-InstallationToken -ModuleName GitHubGovernance { 'fixture-token' }
        Mock Invoke-GitHubGraphQL -ModuleName GitHubGovernance {
            [pscustomobject]@{ enterprise = [pscustomobject]@{
                    ownerInfo = [pscustomobject]@{ twoFactorRequiredSetting = $setting }
                }
            }
        }
        Connect-GHGovernance -Enterprise 'example' -AppClientId 'client' -AppPrivateKey 'unused' | Out-Null
        try {
            $live = Invoke-GHComplianceCheck -CheckId 'enterprise.2fa-required'
        } finally {
            Disconnect-GHGovernance
        }
        $live.status | Should -Be $expected

        $result = @(Test-GHCompliance -DataPath $dataPath -PolicyPath $script:policyPath) |
            Where-Object id -eq 'enterprise:example'
        $failed = @($result.failures | Where-Object check -eq 'enterprise.2fa-required').Count
        $unknown = @($result.notEvaluated | Where-Object check -eq 'enterprise.2fa-required').Count
        $failed | Should -Be ([int]($expected -eq 'fail'))
        $unknown | Should -Be ([int]($expected -eq 'na'))
    }

    It 'does not infer CODEOWNERS results from snapshots with incomplete collection' {
        $script:enterprise | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $dataPath 'enterprise.json')
        $script:organization.codeOwners = @(@{
                repository = 'repo-a'; path = 'CODEOWNERS'; pathEvaluated = $true
                errors = @(); errorsEvaluated = $false
            })
        $script:organization | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $dataPath 'organizations/org-a.json')
        $policy = Get-Content $script:policyPath -Raw | ConvertFrom-Json
        $policy.checks | Add-Member -Force -NotePropertyName 'repo.codeowners-present' -NotePropertyValue @{ enabled = $true; severity = 'medium' }
        $policy.checks | Add-Member -Force -NotePropertyName 'repo.codeowners-valid' -NotePropertyValue @{ enabled = $true; severity = 'medium' }
        $policy | ConvertTo-Json -Depth 20 | Set-Content $script:policyPath

        $result = @(Test-GHCompliance -DataPath $dataPath -PolicyPath $script:policyPath) |
            Where-Object id -eq 'org-a/repo-a'
        @($result.notEvaluated.check) | Should -Contain 'repo.codeowners-valid'
        @($result.notEvaluated.check) | Should -Not -Contain 'repo.codeowners-present'

        $script:organization.codeOwners[0].pathEvaluated = $false
        $script:organization | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $dataPath 'organizations/org-a.json')
        $result = @(Test-GHCompliance -DataPath $dataPath -PolicyPath $script:policyPath) |
            Where-Object id -eq 'org-a/repo-a'
        @($result.notEvaluated.check) | Should -Contain 'repo.codeowners-present'
        @($result.notEvaluated.check) | Should -Contain 'repo.codeowners-valid'
    }

    It 'records an inaccessible CODEOWNERS validation endpoint as incomplete' {
        Mock Invoke-GitHubGraphQL -ModuleName GitHubGovernance {
            [pscustomobject]@{ r0 = [pscustomobject]@{
                    github = [pscustomobject]@{ text = '* @team' }; root = $null; docs = $null
                }
            }
        }
        Mock Invoke-GitHubRest -ModuleName GitHubGovernance { @{ Ok = $false; Data = $null; Status = 403 } }
        $owners = & (Get-Module GitHubGovernance) { Get-CodeOwnersBatch -Org 'org-a' -Repositories @('repo-a') }
        $owners.pathEvaluated | Should -BeTrue
        $owners.errorsEvaluated | Should -BeFalse
    }

    It 'keeps GraphQL location errors scoped to the affected repository' {
        Mock Get-RequestHeaders -ModuleName GitHubGovernance { @{ Authorization = 'Bearer fixture' } }
        Mock Invoke-RestMethod -ModuleName GitHubGovernance {
            [pscustomobject]@{
                data = [pscustomobject]@{
                    r0 = [pscustomobject]@{ github = $null; root = $null; docs = $null }
                    r1 = [pscustomobject]@{ github = $null; root = $null; docs = $null }
                }
                errors = @([pscustomobject]@{ message = 'Unavailable'; path = @('r0', 'github') })
            }
        }
        $owners = & (Get-Module GitHubGovernance) {
            $script:GraphQLUrl = 'https://api.example.test/graphql'
            try {
                Get-CodeOwnersBatch -Org 'org-a' -Repositories @('repo-a', 'repo-b')
            } finally {
                Remove-Variable GraphQLUrl -Scope Script
            }
        }
        ($owners | Where-Object repository -eq 'repo-a').pathEvaluated | Should -BeFalse
        ($owners | Where-Object repository -eq 'repo-b').pathEvaluated | Should -BeTrue
    }

    It 'does not document an unreadable CODEOWNERS location as missing' {
        $markdown = & (Get-Module GitHubGovernance) {
            $lines = [System.Collections.Generic.List[string]]::new()
            $snapshot = [pscustomobject]@{ codeOwners = @(
                    [pscustomobject]@{ repository = 'unknown'; path = $null; pathEvaluated = $false; rules = @(); errors = @(); errorsEvaluated = $false }
                    [pscustomobject]@{ repository = 'known'; path = 'CODEOWNERS'; pathEvaluated = $true; rules = @(); errors = @(); errorsEvaluated = $false }
                )
            }
            Add-CodeOwnersContent -Markdown $lines -Snap $snapshot
            $lines -join "`n"
        }
        $markdown | Should -Not -Match '(?m)^- unknown$'
        $markdown | Should -Match 'Validation errors not available'
    }

    It 'does not fail the ruleset check when detail collection was incomplete' {
        $script:enterprise | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $dataPath 'enterprise.json')
        $script:organization.rulesets = @{ Ok = $true; Data = @(@{ id = 1 }) }
        $script:organization.rulesetDetails = @(@{ id = 1; enforcement = 'active'; target = 'branch' })
        $script:organization.rulesetDetailsComplete = $false
        $script:organization | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $dataPath 'organizations/org-a.json')
        $policy = Get-Content $script:policyPath -Raw | ConvertFrom-Json
        $policy.checks | Add-Member -Force -NotePropertyName 'org.default-branch-ruleset' -NotePropertyValue @{ enabled = $true; severity = 'medium' }
        $policy | ConvertTo-Json -Depth 20 | Set-Content $script:policyPath

        $result = @(Test-GHCompliance -DataPath $dataPath -PolicyPath $script:policyPath) |
            Where-Object id -eq 'org-a'
        @($result.notEvaluated.check) | Should -Contain 'org.default-branch-ruleset'
        @($result.failures.check) | Should -Not -Contain 'org.default-branch-ruleset'
    }

    It 'records an inaccessible ruleset detail as incomplete' {
        Mock Invoke-GitHubRest -ModuleName GitHubGovernance { @{ Ok = $false; Data = $null; Status = 403 } }
        $complete = $true
        $list = [pscustomobject]@{ Ok = $true; Data = @([pscustomobject]@{ id = 1 }) }
        $details = & (Get-Module GitHubGovernance) {
            param($list, [ref] $complete)
            Get-OrgRulesetDetails -Org 'org-a' -RulesetsResult $list -DetailsComplete $complete
        } $list ([ref]$complete)
        $complete | Should -BeFalse
        $details.id | Should -Be 1
    }

    It 'rejects partial GraphQL errors without field paths' {
        Mock Get-RequestHeaders -ModuleName GitHubGovernance { @{ Authorization = 'Bearer fixture' } }
        Mock Invoke-RestMethod -ModuleName GitHubGovernance {
            [pscustomobject]@{
                data = [pscustomobject]@{ r0 = [pscustomobject]@{} }
                errors = @([pscustomobject]@{ message = 'Unscoped error' })
            }
        }
        { & (Get-Module GitHubGovernance) {
                $script:GraphQLUrl = 'https://api.example.test/graphql'
                try {
                    Invoke-GitHubGraphQL -Query 'query { example }' -AllowPartial
                } finally {
                    Remove-Variable GraphQLUrl -Scope Script
                }
            } } |
            Should -Throw '*without a field path*'
    }
}

Describe 'Policy loading from Pester files' {
    It 'loads and evaluates the policy without running the Pester test body' {
        $directory = Join-Path $TestDrive 'example.check'
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
        @(
            'param($ComplianceContext, [switch] $PolicyOnly)'
            'if ($PolicyOnly) { return { param($Snap, $Params) Fail "fixture finding" } }'
            'throw "The Pester test body must not run while loading a policy."'
        ) | Set-Content (Join-Path $directory 'example.check.Tests.ps1')
        $result = & (Get-Module GitHubGovernance) {
            param($path)
            $check = Get-CompliancePolicyCheck -Id 'example.check' -TestsPath $path -Cache @{}
            & $check $null $null
        } $TestDrive
        $result.status | Should -Be 'fail'
        $result.detail | Should -Be 'fixture finding'
    }

    It 'rejects a test file that does not return a policy block' {
        $directory = Join-Path $TestDrive 'invalid.check'
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
        'param($ComplianceContext, [switch] $PolicyOnly) if ($PolicyOnly) { return "invalid" }' |
            Set-Content (Join-Path $directory 'invalid.check.Tests.ps1')
        { & (Get-Module GitHubGovernance) {
                param($path)
                Get-CompliancePolicyCheck -Id 'invalid.check' -TestsPath $path -Cache @{}
            } $TestDrive } | Should -Throw '*does not define a policy script block*'
    }
}
