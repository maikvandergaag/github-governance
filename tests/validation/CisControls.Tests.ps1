BeforeDiscovery {
    $branchCases = @(
        @{ id = 'repo.two-approvals'; type = 'pull_request'; field = 'required_approving_review_count'; good = 2; bad = 1 }
        @{ id = 'repo.dismiss-stale-reviews'; type = 'pull_request'; field = 'dismiss_stale_reviews_on_push'; good = $true; bad = $false }
        @{ id = 'repo.restrict-review-dismissal'; type = 'pull_request'; field = 'dismissal_restriction'; good = @{ enabled = $true }; bad = @{ enabled = $false } }
        @{ id = 'repo.require-codeowner-review'; type = 'pull_request'; field = 'require_code_owner_review'; good = $true; bad = $false }
        @{ id = 'repo.require-status-checks'; type = 'required_status_checks'; field = 'required_status_checks'; good = @(@{ context = 'build' }); bad = @() }
        @{ id = 'repo.require-current-branch'; type = 'required_status_checks'; field = 'strict_required_status_checks_policy'; good = $true; bad = $false }
        @{ id = 'repo.resolve-review-threads'; type = 'pull_request'; field = 'required_review_thread_resolution'; good = $true; bad = $false }
        @{ id = 'repo.linear-history'; type = 'required_linear_history' }
        @{ id = 'repo.signed-commits'; type = 'required_signatures' }
        @{ id = 'repo.restrict-branch-updates'; type = 'update' }
        @{ id = 'repo.deny-force-push'; type = 'non_fast_forward' }
        @{ id = 'repo.deny-branch-deletion'; type = 'deletion' }
    )
    $orgCases = @(
        @{ id = 'org.team-creation-restricted'; field = 'members_can_create_teams'; good = $false; bad = $true }
        @{ id = 'org.verified-domain'; field = 'is_verified'; good = $true; bad = $false }
        @{ id = 'org.repo-deletion-restricted'; field = 'members_can_delete_repositories'; good = $false; bad = $true }
        @{ id = 'org.issue-deletion-restricted'; field = 'members_can_delete_issues'; good = $false; bad = $true }
        @{ id = 'org.private-forking-restricted'; field = 'members_can_fork_private_repositories'; good = $false; bad = $true }
        @{ id = 'org.no-internal-repo-creation'; field = 'members_can_create_internal_repositories'; good = $false; bad = $true }
    )
}

BeforeAll {
    Import-Module "$PSScriptRoot/../../src/GitHubGovernance/GitHubGovernance.psd1" -Force
    function Invoke-Policy($Id, $InputData) {
        $path = "$PSScriptRoot/../$Id/$Id.Tests.ps1"
        $fixture = $InputData | ConvertTo-Json -Depth 20 | ConvertFrom-Json
        & (Get-Module GitHubGovernance) {
            param($path, $fixture)
            $check = & $path -PolicyOnly
            if ($path -match '/repo\.') {
                & $check $fixture $null $null $null
            } else {
                & $check $fixture $null
            }
        } $path $fixture
    }
}

Describe 'CIS branch control evidence' {
    It '<id> distinguishes compliant, missing and inaccessible evidence' -ForEach $branchCases {
        $rule = @{ type = $type }
        if ($field) { $rule.parameters = @{ $field = $good } }
        $fixture = @{
            complianceBranchEvidence = @{
                rules = @{ Ok = $true; Data = @($rule) }
                protection = @{ Ok = $true; Data = $null }
            }
        }
        (Invoke-Policy $id $fixture).status | Should -Be 'pass'
        if ($field) {
            $rule.parameters[$field] = $bad
        } else {
            $fixture.complianceBranchEvidence.rules.Data = @()
        }
        (Invoke-Policy $id $fixture).status | Should -Be 'fail'
        $fixture.complianceBranchEvidence.rules.Ok = $false
        (Invoke-Policy $id $fixture).status | Should -Be 'na'
    }

    It 'accepts an inherited ruleset even if classic protection is inaccessible' {
        $fixture = @{ complianceBranchEvidence = @{
                rules = @{ Ok = $true; Data = @(@{ type = 'pull_request'; parameters = @{ required_approving_review_count = 2 } }) }
                protection = @{ Ok = $false; Status = 404 }
            } }
        (Invoke-Policy 'repo.two-approvals' $fixture).status | Should -Be 'pass'
    }

    It 'accepts qualifying classic protection when no ruleset applies' {
        $fixture = @{ complianceBranchEvidence = @{
                rules = @{ Ok = $true; Data = @() }
                protection = @{ Ok = $true; Data = @{ required_pull_request_reviews = @{ required_approving_review_count = 2 } } }
            } }
        (Invoke-Policy 'repo.two-approvals' $fixture).status | Should -Be 'pass'
    }

    It 'does not interpret an ambiguous classic protection 404 as no protection' {
        Mock Invoke-GitHubRest -ModuleName GitHubGovernance {
            if ($Path -match '/rules/branches/') { return @{ Ok = $true; Data = @() } }
            if ($Path -match '/protection$') { return @{ Ok = $false; Status = 404; Data = $null } }
            return @{ Ok = $true; Data = [pscustomobject]@{ protected = $true } }
        }
        $evidence = & (Get-Module GitHubGovernance) {
            Get-GHBranchEvidence -Organization 'org-a' -Repository 'repo-a' -DefaultBranch 'main'
        }
        (Invoke-Policy 'repo.two-approvals' @{ complianceBranchEvidence = $evidence }).status | Should -Be 'na'
    }
}

Describe 'CIS organization control evidence' {
    It '<id> evaluates settings and preserves missing evidence' -ForEach $orgCases {
        $fixture = @{ settings = @{ Ok = $true; Data = @{ $field = $good } } }
        (Invoke-Policy $id $fixture).status | Should -Be 'pass'
        $fixture.settings.Data[$field] = $bad
        (Invoke-Policy $id $fixture).status | Should -Be 'fail'
        $fixture.settings.Data.Remove($field)
        (Invoke-Policy $id $fixture).status | Should -Be 'na'
    }

    It 'does not treat missing private security defaults as compliant' {
        $fixture = @{ securityConfigDefaults = @{ Ok = $true; Data = @(
                    @{ default_for_new_repos = 'public'; configuration = @{ dependabot_alerts = 'enabled' } }
                ) } }
        (Invoke-Policy 'org.dependabot-alerts-new-repos' $fixture).status | Should -Be 'na'
        $fixture.securityConfigDefaults.Data += @{ default_for_new_repos = 'private_and_internal'; configuration = @{ dependabot_alerts = 'disabled' } }
        (Invoke-Policy 'org.dependabot-alerts-new-repos' $fixture).status | Should -Be 'fail'
    }

    It 'checks webhook HTTPS and treats incomplete webhook settings as unknown' {
        $fixture = @{ webhooks = @{ Ok = $true; Data = @(@{ config = @{ url = 'http://example.test'; insecure_ssl = '0' } }) } }
        (Invoke-Policy 'org.webhooks-tls' $fixture).status | Should -Be 'fail'
        $fixture.webhooks.Data[0].config.url = 'https://example.test'
        (Invoke-Policy 'org.webhooks-tls' $fixture).status | Should -Be 'pass'
        $fixture.webhooks.Data[0].config.Remove('insecure_ssl')
        (Invoke-Policy 'org.webhooks-tls' $fixture).status | Should -Be 'na'
    }

    It 'checks organization workflow token permissions' {
        $fixture = @{ actionsWorkflowPermissions = @{ Ok = $true; Data = @{
                    default_workflow_permissions = 'read'; can_approve_pull_request_reviews = $false
                } } }
        (Invoke-Policy 'org.actions-token-read-only' $fixture).status | Should -Be 'pass'
        (Invoke-Policy 'org.actions-no-pr-approval' $fixture).status | Should -Be 'pass'
        $fixture.actionsWorkflowPermissions.Data.default_workflow_permissions = 'write'
        $fixture.actionsWorkflowPermissions.Data.can_approve_pull_request_reviews = $true
        (Invoke-Policy 'org.actions-token-read-only' $fixture).status | Should -Be 'fail'
        (Invoke-Policy 'org.actions-no-pr-approval' $fixture).status | Should -Be 'fail'
    }

    It 'checks app and secret scope without assuming incomplete data is compliant' {
        $fixture = @{ installations = @{ Ok = $true; Data = @(@{ repository_selection = 'all' }) } }
        (Invoke-Policy 'org.apps-selected-repositories' $fixture).status | Should -Be 'fail'
        $fixture.installations.Data[0].repository_selection = 'selected'
        (Invoke-Policy 'org.apps-selected-repositories' $fixture).status | Should -Be 'pass'
        $fixture.installations.Data[0].Remove('repository_selection')
        (Invoke-Policy 'org.apps-selected-repositories' $fixture).status | Should -Be 'na'
        $fixture.installations.Data = @()
        (Invoke-Policy 'org.apps-selected-repositories' $fixture).status | Should -Be 'pass'

        $fixture = @{ actionsSecrets = @{ Ok = $true; Data = @(@{ visibility = 'all' }) } }
        (Invoke-Policy 'org.secrets-limited-repositories' $fixture).status | Should -Be 'fail'
        $fixture.actionsSecrets.Data[0].visibility = 'selected'
        (Invoke-Policy 'org.secrets-limited-repositories' $fixture).status | Should -Be 'pass'
    }
}
