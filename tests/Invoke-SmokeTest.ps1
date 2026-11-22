<#
.SYNOPSIS
    End-to-end smoke test of the GitHubGovernance module against a fake GitHub API.

.DESCRIPTION
    Replaces Invoke-RestMethod inside the module with a fixture router, so the real code paths run:
    GitHub App JWT + installation tokens per enterprise/organization, REST pagination wrappers,
    GraphQL, snapshots, Markdown rendering, compliance checks, report, SARIF and issue sync (dry run).
    No network access or credentials needed. Exit code 1 on any failed assertion.

.EXAMPLE
    pwsh ./tests/Invoke-SmokeTest.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$work = Join-Path ([System.IO.Path]::GetTempPath()) "ghe-docs-smoke-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
New-Item -ItemType Directory -Path $work | Out-Null

Import-Module (Join-Path $root 'src/GitHubGovernance/GitHubGovernance.psd1') -Force
$module = Get-Module GitHubGovernance

$script:failures = [System.Collections.Generic.List[string]]::new()
function Assert-That {
    param([bool] $Condition, [string] $Message)
    if ($Condition) {
        Write-Host "  [PASS] $Message" -ForegroundColor Green
    } else {
        Write-Host "  [FAIL] $Message" -ForegroundColor Red; $script:failures.Add($Message)
    }
}

#region Fake GitHub API (runs inside the module scope)

& $module {
    $global:GHESmokeCalls = [System.Collections.Generic.List[string]]::new()
    $global:GHESmokeErrorPath = ''
    $global:GHESmokePat = $false

    function script:New-HttpError([int] $Code) {
        $response = [System.Net.Http.HttpResponseMessage]::new([System.Net.HttpStatusCode]$Code)
        return [Microsoft.PowerShell.Commands.HttpResponseException]::new("Response status code does not indicate success: $Code", $response)
    }

    function script:Invoke-RestMethod {
        [CmdletBinding()]
        param($Uri, $Headers, $Method = 'Get', $Body, $ContentType, $ResponseHeadersVariable)
        $path = ([uri]$Uri).PathAndQuery.TrimStart('/') -replace '[?&]per_page=100', ''
        $auth = [string]$Headers.Authorization
        $global:GHESmokeCalls.Add("$Method $path | $auth")
        if ($global:GHESmokeErrorPath -and $path -eq $global:GHESmokeErrorPath) {
            throw 'Fixture API failure'
        }

        # --- GitHub App installation flow (JWT)
        if ($path -match '^enterprises/contoso/installation$') {
            return [pscustomobject]@{ id = 100 }
        }
        if ($path -match '^orgs/(org-a|org-b)/installation$') {
            return [pscustomobject]@{ id = $(if ($Matches[1] -eq 'org-a') {
                        101
                    } else {
                        102
                    })
            }
        }
        if ($path -match '^orgs/[^/]+/installation$') {
            throw (New-HttpError 404)
        }   # org-c: App not installed
        if ($path -match '^app/installations/(\d+)/access_tokens$') {
            return [pscustomobject]@{ token = "inst-$($Matches[1])"; expires_at = [DateTimeOffset]::UtcNow.AddHours(1).ToString('o') }
        }

        # --- Every other call must use the right installation token
        $expected = if ($global:GHESmokePat) {
            'Bearer fixture-pat'
        } elseif ($path -match '^(orgs|repos)/(org-a|org-b)') {
            "Bearer inst-$(if ($Matches[2] -eq 'org-a') { 101 } else { 102 })"
        } else {
            'Bearer inst-100'
        }
        if ($path -like 'repos/contoso/github-docs/*') {
            # Docs repository: must use the workflow token, never the App.
            if ($auth -ne 'Bearer fake') {
                throw "Docs repository called with $auth"
            }
        } elseif ($path -ne 'graphql' -and $auth -ne $expected) {
            throw "Wrong token for $path ($auth, expected $expected)"
        }

        # --- GraphQL
        if ($path -eq 'graphql') {
            $query = ($Body | ConvertFrom-Json).query
            if ($query -match 'organizations\(first') {
                return [pscustomobject]@{ data = [pscustomobject]@{ enterprise = [pscustomobject]@{
                            name = 'Contoso'; slug = 'contoso'; createdAt = '2024-01-01T00:00:00Z'
                            organizations = [pscustomobject]@{ pageInfo = [pscustomobject]@{ hasNextPage = $false; endCursor = $null }
                                nodes = @([pscustomobject]@{ login = 'org-b'; name = 'B' }, [pscustomobject]@{ login = 'org-a'; name = 'A' }, [pscustomobject]@{ login = 'org-c'; name = 'C' })
                            }
                        }
                    }
                }
            }
            if ($query -match 'ownerInfo') {
                return [pscustomobject]@{
                    errors = $(if ($query -match 'samlIdentityProvider') {
                            @([pscustomobject]@{ message = 'Resource not accessible'; path = @('enterprise', 'ownerInfo', 'samlIdentityProvider') })
                        } else {
                            @()
                        })
                    data = [pscustomobject]@{ enterprise = [pscustomobject]@{
                            members = [pscustomobject]@{ totalCount = 120 }
                            billingInfo = [pscustomobject]@{ totalLicenses = 150; totalAvailableLicenses = 30; allLicensableUsersCount = 120 }
                            rulesets = [pscustomobject]@{ nodes = @([pscustomobject]@{ databaseId = 77; name = 'ent-main' }) }
                            ownerInfo = [pscustomobject]@{
                                twoFactorRequiredSetting = 'NO_POLICY'; twoFactorDisallowedMethodsSetting = 'NONE'; affiliatedUsersWithTwoFactorDisabledExist = $true
                                defaultRepositoryPermissionSetting = 'READ'; membersCanCreateRepositoriesSetting = 'PRIVATE'; membersCanCreatePublicRepositoriesSetting = $false
                                membersCanCreatePrivateRepositoriesSetting = $true; membersCanCreateInternalRepositoriesSetting = $true
                                membersCanChangeRepositoryVisibilitySetting = 'NO_POLICY'; membersCanDeleteRepositoriesSetting = 'DISABLED'; membersCanDeleteIssuesSetting = 'NO_POLICY'
                                membersCanInviteCollaboratorsSetting = 'ENABLED'; membersCanUpdateProtectedBranchesSetting = 'DISABLED'; allowPrivateRepositoryForkingSetting = 'DISABLED'
                                repositoryDeployKeySetting = 'NO_POLICY'; ipAllowListEnabledSetting = 'ENABLED'; ipAllowListForInstalledAppsEnabledSetting = 'DISABLED'
                                ipAllowListEntries = [pscustomobject]@{ totalCount = 1; nodes = @([pscustomobject]@{ name = 'Office'; allowListValue = '203.0.113.0/24'; isActive = $true }) }
                                samlIdentityProvider = $null; oidcProvider = [pscustomobject]@{ providerType = 'AAD'; tenantId = 't' }
                                admins = [pscustomobject]@{ totalCount = 4; nodes = @('maik', 'a', 'b', 'c' | ForEach-Object { [pscustomobject]@{ login = $_ } }) }
                                outsideCollaborators = [pscustomobject]@{ totalCount = 7 }
                            }
                        }
                    }
                }
            }
            if ($query -match 'CODEOWNERS') {
                if ($query -match 'repository\(owner:\s*\$owner,\s*name:\s*\$name\)') {
                    $name = ($Body | ConvertFrom-Json).variables.name
                    return [pscustomobject]@{ data = [pscustomobject]@{ repository = [pscustomobject]@{
                                github = $null; root = $(if ($name -eq 'api') {
                                        [pscustomobject]@{ text = '* @org-a/platform' }
                                    } else {
                                        $null
                                    }); docs = $null
                            }
                        }
                    }
                }
                $co = "# Global owners`n*  @org-a/platform  # default`n/infra/ @org-a/cloud-team maik@example.com`n`n/docs/`n*.ps1 @org-a/platform @judith"
                return [pscustomobject]@{ data = [pscustomobject]@{
                        r0 = [pscustomobject]@{ github = $null; root = [pscustomobject]@{ text = $co }; docs = $null }
                        r1 = [pscustomobject]@{ github = $null; root = $null; docs = $null }
                    }
                }
            }
            throw "Unexpected GraphQL query: $query"
        }

        # --- Enterprise REST
        switch -Regex ($path) {
            '^enterprises/contoso/rulesets/77$' {
                return [pscustomobject]@{ id = 77; name = 'ent-main'; target = 'branch'; enforcement = 'evaluate'; conditions = [pscustomobject]@{ ref_name = [pscustomobject]@{ include = @('~DEFAULT_BRANCH'); exclude = @() } }; bypass_actors = @(); rules = @([pscustomobject]@{ type = 'non_fast_forward' }) }
            }
            '^enterprises/contoso/actions/permissions$' {
                return [pscustomobject]@{ enabled_organizations = 'all'; allowed_actions = 'all' }
            }
            '^enterprises/contoso/actions/runners$' {
                return [pscustomobject]@{ total_count = 0; runners = @() }
            }
            '^enterprises/contoso/code-security/configurations$' {
                return , @([pscustomobject]@{ name = 'Ent baseline'; advanced_security = 'enabled'; secret_scanning = 'enabled'; secret_scanning_push_protection = 'enabled'; enforcement = 'enforced' })
            }
            '^enterprises/' {
                throw (New-HttpError 404)
            }
        }

        # --- Organization REST (org-a and org-b identical)
        $repos = @(
            [pscustomobject]@{ name = 'api'; visibility = 'internal'; archived = $false; default_branch = 'main'; language = 'C#'; pushed_at = (Get-Date).AddDays(-10).ToString('o'); security_and_analysis = [pscustomobject]@{ advanced_security = [pscustomobject]@{ status = 'enabled' }; secret_scanning = [pscustomobject]@{ status = 'enabled' }; secret_scanning_push_protection = [pscustomobject]@{ status = 'enabled' } } }
            [pscustomobject]@{ name = 'web'; visibility = 'public'; archived = $false; default_branch = 'main'; language = 'TS'; pushed_at = (Get-Date).AddDays(-500).ToString('o'); security_and_analysis = [pscustomobject]@{ advanced_security = [pscustomobject]@{ status = 'enabled' }; secret_scanning = [pscustomobject]@{ status = 'disabled' }; secret_scanning_push_protection = [pscustomobject]@{ status = 'disabled' } } }
            [pscustomobject]@{ name = 'old'; visibility = 'private'; archived = $true; default_branch = 'master'; language = $null; pushed_at = '2020-01-01T00:00:00Z' }
        )
        switch -Regex ($path) {
            '^orgs/[^/]+/rulesets/1$' {
                return [pscustomobject]@{ id = 1; name = 'main-protect'; target = 'branch'; enforcement = 'active'; conditions = [pscustomobject]@{ ref_name = [pscustomobject]@{ include = @('~DEFAULT_BRANCH'); exclude = @() } }; bypass_actors = @([pscustomobject]@{ actor_id = 5; actor_type = 'Team'; bypass_mode = 'pull_request' }); rules = @([pscustomobject]@{ type = 'pull_request'; parameters = [pscustomobject]@{ required_approving_review_count = 2 } }) }
            }
            '^orgs/[^/]+/rulesets$' {
                return , @([pscustomobject]@{ id = 1; name = 'main-protect'; target = 'branch'; enforcement = 'active'; source_type = 'Organization'; source = 'org' })
            }
            '^orgs/[^/]+/teams$' {
                return , @([pscustomobject]@{ name = 'Platform | Ops'; slug = 'platform'; privacy = 'closed'; parent = $null; description = "multi`nline" })
            }
            '^orgs/[^/]+/members\?role=admin$' {
                return , @([pscustomobject]@{ login = 'maik' })
            }
            '^orgs/[^/]+/members$' {
                return , @([pscustomobject]@{ login = 'maik' }, [pscustomobject]@{ login = 'judith' })
            }
            '^orgs/[^/]+/outside_collaborators$' {
                return , @()
            }
            '^orgs/[^/]+/actions/permissions$' {
                return [pscustomobject]@{ enabled_repositories = 'all'; allowed_actions = 'selected' }
            }
            '^orgs/[^/]+/actions/runners$' {
                return [pscustomobject]@{ runners = @([pscustomobject]@{ name = 'r1'; os = 'Linux'; status = 'online'; labels = @([pscustomobject]@{ name = 'self-hosted' }) }) }
            }
            '^orgs/[^/]+/actions/runner-groups$' {
                return [pscustomobject]@{ runner_groups = @() }
            }
            '^orgs/[^/]+/installations$' {
                return [pscustomobject]@{ installations = @([pscustomobject]@{ app_slug = 'renovate'; repository_selection = 'all'; permissions = [pscustomobject]@{ contents = 'write' }; created_at = '2025-01-01' }) }
            }
            '^orgs/[^/]+/copilot/billing$' {
                return [pscustomobject]@{ plan_type = 'business'; seat_breakdown = [pscustomobject]@{ total = 12 } }
            }
            '^orgs/[^/]+/hooks$' {
                return , @([pscustomobject]@{ active = $true; events = @('push'); config = [pscustomobject]@{ url = 'https://hook.example'; content_type = 'json'; insecure_ssl = '1'; secret = '********' } })
            }
            '^orgs/[^/]+/actions/secrets$' {
                return [pscustomobject]@{ secrets = @([pscustomobject]@{ name = 'AZURE_CLIENT_ID'; visibility = 'private'; updated_at = '2026-10-01' }) }
            }
            '^orgs/[^/]+/actions/variables$' {
                return [pscustomobject]@{ variables = @([pscustomobject]@{ name = 'REGION'; value = 'westeurope-SECRETVALUE'; visibility = 'all' }) }
            }
            '^orgs/[^/]+/code-security/configurations$' {
                return , @()
            }
            '^orgs/[^/]+/properties/schema$' {
                return , @()
            }
            '^orgs/[^/]+/custom-repository-roles$' {
                return [pscustomobject]@{ total_count = 0; custom_roles = @() }
            }
            '^orgs/[^/]+/repos\?type=all$' {
                return , $repos
            }
            '^repos/[^/]+/api/codeowners/errors$' {
                return [pscustomobject]@{ errors = @([pscustomobject]@{ line = 3; kind = 'Unknown owner'; message = 'Unknown owner on line 3: @org-a/cloud-team' }) }
            }
            '^repos/[^/]+/(api|web)$' {
                return ($repos | Where-Object name -eq $Matches[1])
            }
            '^orgs/[^/]+$' {
                return [pscustomobject]@{ name = 'Org'; two_factor_requirement_enabled = $true; default_repository_permission = 'read'; members_can_create_public_repositories = $false; secret_scanning_push_protection_enabled_for_new_repositories = $true }
            }
            # --- Docs repository issues API (Sync-GHComplianceIssue)
            '^repos/contoso/github-docs/issues\?state=open' {
                return , @()
            }
            '^repos/contoso/github-docs/labels$' {
                return , @()
            }
        }
        throw "Unexpected request: $Method $path"
    }
}

#endregion

try {
    Push-Location $work
    New-Item -ItemType Directory -Path 'compliance' | Out-Null
    Copy-Item (Join-Path $root 'compliance/policy.json') 'compliance/policy.json'
    New-Item -ItemType Directory -Path 'docs/configuration' -Force | Out-Null
    Copy-Item -Path (Join-Path $root 'docs/configuration/*') -Destination 'docs/configuration' -Recurse

    # Throwaway App key, generated in-process.
    $rsa = [System.Security.Cryptography.RSA]::Create(2048)
    $pem = $rsa.ExportRSAPrivateKeyPem()

    Write-Host "`nConnection"
    $conn = Connect-GHGovernance -Enterprise contoso -AppClientId 'Iv23liSMOKE' -AppPrivateKey $pem
    Assert-That ($conn.AuthMode -eq 'App') 'Connects in GitHub App mode'

    $jwtCall = ($global:GHESmokeCalls | Where-Object { $_ -like 'Get enterprises/contoso/installation*' } | Select-Object -First 1)
    $jwt = ($jwtCall -split 'Bearer ')[1]
    $parts = $jwt.Split('.')
    $toBytes = { param($s) $p = $s.Replace('-', '+').Replace('_', '/'); [Convert]::FromBase64String($p.PadRight($p.Length + (4 - $p.Length % 4) % 4, '=')) }
    $validSig = $rsa.VerifyData([Text.Encoding]::UTF8.GetBytes("$($parts[0]).$($parts[1])"), (& $toBytes $parts[2]),
        [System.Security.Cryptography.HashAlgorithmName]::SHA256, [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)
    Assert-That $validSig 'App JWT is signed correctly (RS256)'

    Write-Host "`nFocused getters"
    $orgs = Get-GHOrganization
    Assert-That (($orgs.login -join ',') -eq 'org-a,org-b,org-c') 'Get-GHOrganization lists organizations sorted'
    Assert-That ((Get-GHOrganizationSetting org-a).two_factor_requirement_enabled -eq $true) 'Get-GHOrganizationSetting returns settings'
    $teams = 'org-a', 'org-b' | Get-GHOrganizationTeam
    Assert-That (@($teams).Count -eq 2 -and $teams[0].organization -eq 'org-a') 'Getters accept pipeline input and tag the organization'
    Assert-That ((Get-GHOrganizationRuleset org-a).rules[0].type -eq 'pull_request') 'Get-GHOrganizationRuleset returns rule details'
    $hook = Get-GHOrganizationWebhook org-a
    Assert-That (-not $hook.config.PSObject.Properties['secret']) 'Webhook secrets are stripped'
    $actions = Get-GHOrganizationActionsSetting org-a
    Assert-That (-not $actions.Variables[0].PSObject.Properties['value']) 'Variable values are stripped'
    Assert-That (@(Get-GHRepository org-a).Count -eq 2) 'Get-GHRepository excludes archived repositories by default'
    $co = Get-GHCodeOwners org-a
    Assert-That (($co | Where-Object repository -eq 'api').rules.Count -eq 4) 'Get-GHCodeOwners parses CODEOWNERS rules'
    Assert-That (-not ($co | Where-Object repository -eq 'web').path) 'Get-GHCodeOwners reports missing CODEOWNERS'
    $policy = Get-GHEnterprisePolicy -WarningAction SilentlyContinue
    Assert-That ($policy.ownerInfo.twoFactorRequiredSetting -eq 'NO_POLICY') 'Get-GHEnterprisePolicy returns ownerInfo'
    Assert-That ((Get-GHEnterpriseRuleset).name -eq 'ent-main') 'Get-GHEnterpriseRuleset returns enterprise rulesets'
    $err = $null
    Get-GHOrganizationSetting org-c -ErrorVariable err -ErrorAction SilentlyContinue | Out-Null
    Assert-That ($err -and "$err" -like '*not installed*') 'Org without App installation gives a clear error'

    Write-Host "`nExport"
    Export-GHDocumentation -OutputPath 'docs/enterprise' -WarningAction SilentlyContinue 6>$null
    $expected = 'docs/enterprise/README.md', 'docs/enterprise/enterprise/README.md', 'docs/enterprise/enterprise/rulesets.md',
    'docs/enterprise/organizations/org-a/README.md', 'docs/enterprise/organizations/org-a/codeowners.md',
    'docs/enterprise/organizations/org-a/repositories.md', 'docs/enterprise/_data/enterprise.json', 'docs/enterprise/_data/organizations/org-a.json'
    Assert-That (@($expected | Where-Object { -not (Test-Path $_) }).Count -eq 0) 'Expected folder structure is generated'
    Assert-That ((Get-Content docs/enterprise/README.md -Raw) -match 'Configuration handbook' -and
        (Get-Content docs/enterprise/enterprise/README.md -Raw) -match 'Configuration handbook' -and
        (Get-Content docs/enterprise/organizations/org-a/README.md -Raw) -match 'Configuration handbook') 'Generated documentation links to the configuration handbook'
    Assert-That ((Get-Content docs/enterprise/README.md -Raw) -match 'not installed on: `org:org-c`') 'Index warns about organizations without the App'
    Assert-That (-not (Select-String -Path 'docs/enterprise/_data/organizations/*.json' -Pattern 'SECRETVALUE|\*\*\*\*' -Quiet)) 'No secret values in snapshots'

    $broken = foreach ($md in Get-ChildItem docs/enterprise -Recurse -Filter *.md) {
        foreach ($m in [regex]::Matches((Get-Content $md.FullName -Raw), '\]\(([^)#:]+\.md)\)')) {
            if ($m.Groups[1].Value -like '*compliance/README.md') {
                continue
            }  # written by Test-GHCompliance
            if (-not (Test-Path (Join-Path $md.DirectoryName $m.Groups[1].Value))) {
                "$($md.Name) -> $($m.Groups[1].Value)"
            }
        }
    }
    Assert-That (@($broken).Count -eq 0) "All relative links resolve $(if ($broken) { ": $($broken -join '; ')" })"

    Write-Host "`nCompliance"
    $findings = Test-GHCompliance -DataPath docs/enterprise/_data -PolicyPath compliance/policy.json -OutputFile findings.json -ReportFile docs/enterprise/compliance/README.md 6>$null
    Assert-That ((Get-Content docs/enterprise/compliance/README.md -Raw) -match 'Configuration handbook') 'Generated compliance report links to the configuration handbook'
    $byId = @{}; $findings | ForEach-Object { $byId[$_.id] = $_ }
    $failed = { param($id) @($byId[$id].failures | ForEach-Object { $_.check }) }
    Assert-That ('enterprise.2fa-required' -in (& $failed 'enterprise:contoso')) 'Enterprise NO_POLICY 2FA is a finding'
    Assert-That ('enterprise.sso-configured' -notin (& $failed 'enterprise:contoso')) 'OIDC counts as SSO although SAML is unreadable'
    Assert-That ('org.webhooks-tls' -in (& $failed 'org-a')) 'Webhook without TLS verification is a finding'
    Assert-That (@('repo.not-public', 'repo.secret-scanning', 'repo.codeowners-present', 'repo.stale' | Where-Object { $_ -notin (& $failed 'org-a/web') }).Count -eq 0) 'Repository findings are detected'
    Assert-That ('repo.codeowners-valid' -in (& $failed 'org-a/api')) 'CODEOWNERS errors are a finding'
    Assert-That (-not $byId.ContainsKey('org-a/old')) 'Archived repositories are not evaluated'
    Assert-That (@($byId['org-c'].notEvaluated).Count -gt 0 -and @($byId['org-c'].failures).Count -eq 0) 'Org without App: checks not evaluated, no false findings'
    Assert-That ((Get-Content docs/enterprise/compliance/README.md -Raw) -match '## By requirement') 'Compliance report is written'

    Write-Host "`nLive Pester compliance"
    $tokensBefore = @($global:GHESmokeCalls | Where-Object { $_ -like 'Post app/installations/*/access_tokens*' }).Count
    $global:LASTEXITCODE = 0
    $live = Test-GHCompliance -UsePester -DataPath docs/enterprise/_data -PolicyPath compliance/policy.json `
        -OutputFile live-findings.json -ReportFile docs/enterprise/compliance/README.md -WarningAction SilentlyContinue 6>$null
    Assert-That ($global:LASTEXITCODE -eq 0) 'Expected compliance failures do not set a failing process exit code'
    $liveById = @{}; $live | ForEach-Object { $liveById[$_.id] = $_ }
    Assert-That (@($liveById['enterprise:contoso'].failures | Where-Object check -eq 'enterprise.2fa-required').Count -eq 1) 'Live enterprise Pester failure is reported'
    Assert-That (@($liveById['org-a'].failures | Where-Object check -eq 'org.webhooks-tls').Count -eq 1) 'Live organization Pester failure is reported'
    Assert-That (@($liveById['org-a/web'].failures | Where-Object check -eq 'repo.not-public').Count -eq 1) 'Live repository Pester failure is reported'
    Assert-That (@($liveById['org-c'].notEvaluated).Count -gt 0 -and @($liveById['org-c'].failures).Count -eq 0) 'Missing installation stays not evaluated in Pester'
    Assert-That (@($global:GHESmokeCalls | Where-Object { $_ -like 'Post app/installations/*/access_tokens*' }).Count -eq $tokensBefore) 'Live checks reuse scoped installation tokens'
    $singlePolicy = [pscustomobject]@{
        checks = [pscustomobject]@{ 'org.webhooks-tls' = [pscustomobject]@{ enabled = $true; severity = 'high' } }
        exemptions = [pscustomobject]@{}
    }
    Remove-Variable LASTEXITCODE -Scope Global -ErrorAction Ignore
    & $module {
        param($policy, $path)
        $checks = Get-GHComplianceChecks -TestsPath $path
        Invoke-GHPesterChecks -Checks $checks.org -TargetId 'org-a' -Organization 'org-a' -Policy $policy -TestsPath $path
    } $singlePolicy (Join-Path $root 'tests') | Out-Null
    Assert-That ($null -eq (Get-Variable LASTEXITCODE -Scope Global -ErrorAction Ignore)) 'Pester does not introduce an exit code when none existed'
    $global:LASTEXITCODE = 0
    $live | ConvertTo-GHComplianceSarif -OutputFile live.sarif 6>$null
    Assert-That (@((Get-Content live.sarif -Raw | ConvertFrom-Json).runs[0].results | Where-Object { $_.ruleId -eq 'repo.not-public' -and $_.properties.target -eq 'org-a/web' }).Count -eq 1) 'Live Pester findings reach SARIF'
    $liveIssueOutput = Sync-GHComplianceIssue -FindingsFile live-findings.json -Repository contoso/github-docs -Token 'fake' -DryRun -MaxNewIssues 3 -WarningAction SilentlyContinue 6>&1 | Out-String
    Assert-That ($liveIssueOutput -match 'created: 3') 'Live Pester findings reach issue sync'
    $policy = Get-Content compliance/policy.json -Raw | ConvertFrom-Json
    $policy.checks.'enterprise.max-owners'.params.max = 5
    $policy.exemptions | Add-Member -NotePropertyName 'org-a/web' -NotePropertyValue @('repo.not-public')
    $policy | ConvertTo-Json -Depth 10 | Set-Content compliance/policy-custom.json
    $global:LASTEXITCODE = 73
    $custom = Test-GHCompliance -UsePester -DataPath docs/enterprise/_data -PolicyPath compliance/policy-custom.json -SkipCodeOwners -WarningAction SilentlyContinue 6>$null
    Assert-That ($global:LASTEXITCODE -eq 73) 'Pester execution preserves the caller exit code'
    $global:LASTEXITCODE = 0
    $customById = @{}; $custom | ForEach-Object { $customById[$_.id] = $_ }
    Assert-That (@($customById['enterprise:contoso'].failures | Where-Object check -eq 'enterprise.max-owners').Count -eq 0) 'Live Pester honors central policy parameters'
    Assert-That (@($customById['org-a/web'].failures | Where-Object check -eq 'repo.not-public').Count -eq 0) 'Live Pester honors target exemptions'
    Assert-That (@($customById['org-a/api'].notEvaluated | Where-Object check -like 'repo.codeowners-*').Count -eq 2) 'Skipped CODEOWNERS checks remain not evaluated'
    $global:GHESmokeErrorPath = 'orgs/org-a/actions/permissions'
    $errorRaised = $false
    try {
        Test-GHCompliance -UsePester -DataPath docs/enterprise/_data -PolicyPath compliance/policy.json -OutputFile failed-findings.json 6>$null | Out-Null
    } catch {
        $errorRaised = $_.Exception.Message -match 'Fixture API failure'
    } finally {
        $global:GHESmokeErrorPath = ''
    }
    Assert-That ($errorRaised -and -not (Test-Path failed-findings.json)) 'Unexpected Pester errors stop the run without publishing findings'
    $global:GHESmokeErrorPath = 'orgs/org-error/installation'
    $authErrorRaised = $false
    try {
        & $module { Get-InstallationToken -Scope 'org:org-error' } | Out-Null
    } catch {
        $authErrorRaised = $_.Exception.Message -match 'Fixture API failure'
    } finally {
        $global:GHESmokeErrorPath = ''
    }
    Assert-That $authErrorRaised 'Unexpected installation lookup errors are not mistaken for missing installations'
    New-Item -ItemType Directory -Path 'broken-tests/org.2fa-required' -Force | Out-Null
    @{
        id = 'org.2fa-required'; scope = 'org'; title = 'Two-factor authentication is required'
        remediation = 'Require two-factor authentication.'
        dataSource = @{ type = 'organization-section'; section = 'settings' }
    } | ConvertTo-Json -Depth 5 | Set-Content 'broken-tests/org.2fa-required/check.json'
    @{ enabled = $true; severity = 'high' } | ConvertTo-Json | Set-Content 'broken-tests/org.2fa-required/policy.json'
    'Require two-factor authentication.' | Set-Content 'broken-tests/org.2fa-required/issue.md'
    @'
param($ComplianceContext, [switch] $PolicyOnly)
if ($PolicyOnly) { return { param($Snap, $Params) Pass } }
Describe 'Broken check' {
    It 'fails unexpectedly after recording a result' {
        $ComplianceContext.Result = @{ status = 'fail'; detail = 'Expected failure' }
        throw 'Unexpected test error'
    }
}
'@ | Set-Content 'broken-tests/org.2fa-required/org.2fa-required.Tests.ps1'
    $brokenPolicy = [pscustomobject]@{
        checks = [pscustomobject]@{ 'org.2fa-required' = [pscustomobject]@{ enabled = $true } }
        exemptions = [pscustomobject]@{}
    }
    $unexpectedRaised = $false
    try {
        & $module {
            param($policy, $path)
            $checks = Get-GHComplianceChecks -TestsPath $path
            Invoke-GHPesterChecks -Checks $checks.org -TargetId 'org-a' -Organization 'org-a' -Policy $policy -TestsPath $path
        } $brokenPolicy (Join-Path $work 'broken-tests') | Out-Null
    } catch {
        $unexpectedRaised = $_.Exception.Message -match 'Unexpected test error'
    }
    Assert-That $unexpectedRaised 'Unexpected errors cannot be mistaken for failed assertions'
    Write-Host "`nSARIF and issues"
    $findings | ConvertTo-GHComplianceSarif -OutputFile compliance.sarif `
        -ServerUrl 'https://docs.ghe.com' -Repository 'contoso/github-docs' -Commit 'abc123' `
        -EnterpriseApiUrl 'https://api.contoso.ghe.com' 6>$null
    $sarif = Get-Content compliance.sarif -Raw | ConvertFrom-Json
    $result = $sarif.runs[0].results | Where-Object { $_.ruleId -eq 'repo.secret-scanning' -and $_.properties.target -eq 'org-a/web' }
    $loc = $result.locations[0].physicalLocation
    $line = (Get-Content $loc.artifactLocation.uri)[$loc.region.startLine - 1]
    Assert-That ($line -like '| web |*') 'SARIF alert points at the repository row'
    $rule = $sarif.runs[0].tool.driver.rules | Where-Object { $_.id -eq 'repo.secret-scanning' }
    Assert-That ($result.message.text -match 'Secret scanning is `disabled`' -and
        $result.message.text -match 'Expected: Secret scanning is enabled' -and
        $result.message.text.Contains('https://contoso.ghe.com/org-a/web') -and
        $result.message.text.Contains("https://docs.ghe.com/contoso/github-docs/blob/abc123/$($loc.artifactLocation.uri)#L$($loc.region.startLine)")) 'SARIF result includes observed value, requirement and target-specific links'
    $otherTarget = $sarif.runs[0].results | Where-Object { $_.ruleId -eq 'repo.secret-scanning' -and $_.properties.target -eq 'org-b/web' }
    Assert-That ($otherTarget.message.text.Contains('https://contoso.ghe.com/org-b/web') -and
        -not $otherTarget.message.text.Contains('https://contoso.ghe.com/org-a/web')) 'SARIF keeps links specific to each target of the same rule'
    Assert-That ($rule.help.markdown -match 'Potential impact' -and $rule.help.markdown -match 'Leaked credentials' -and
        $rule.help.markdown -match 'Attach a code security configuration' -and $rule.help.markdown -match 'rerun the compliance workflow' -and
        $rule.help.markdown -match 'https://docs.github.com/en/code-security/secret-scanning') 'SARIF rule help explains impact, remediation, verification and reference'
    $ownerResult = $sarif.runs[0].results | Where-Object { $_.ruleId -eq 'enterprise.max-owners' }
    Assert-That ($ownerResult.message.text -match '4 enterprise owners \(max 3\)' -and
        $ownerResult.message.text -match '"max":3' -and
        $ownerResult.message.text.Contains('https://contoso.ghe.com/enterprises/contoso')) 'SARIF result includes configured policy threshold and enterprise link'
    $allChecks = & $module {
        param($testsPath)
        $checks = Get-GHComplianceChecks -TestsPath $testsPath
        foreach ($scope in @('enterprise', 'org', 'repo')) {
            foreach ($id in $checks[$scope].Keys) {
                [pscustomobject]@{
                    check = $id
                    title = $checks[$scope][$id].Title
                    remediation = $checks[$scope][$id].Remediation
                    severity = 'medium'
                    detail = 'test'
                }
            }
        }
    } (Join-Path $root 'tests')
    $allTarget = [pscustomobject]@{ id = 'org-a/web'; type = 'repo'; org = 'org-a'; repo = 'web'; docs = 'docs/enterprise/organizations/org-a/repositories.md'; failures = $allChecks }
    $allTarget | ConvertTo-GHComplianceSarif -OutputFile all-checks.sarif 6>$null
    $allRules = (Get-Content all-checks.sarif -Raw | ConvertFrom-Json).runs[0].tool.driver.rules
    Assert-That ($allRules.Count -eq $allChecks.Count -and @($allRules | Where-Object { $_.help.markdown -notmatch '## Potential impact' }).Count -eq 0) 'Every compliance rule explains its potential impact'
    $fingerprint = $result.partialFingerprints.'gheComplianceTargetCheck/v1'
    $other = $sarif.runs[0].results | Where-Object { $_.ruleId -eq 'repo.not-public' -and $_.properties.target -eq 'org-a/web' }
    Assert-That ($fingerprint -and $fingerprint -ne $other.partialFingerprints.'gheComplianceTargetCheck/v1' -and
        -not $result.partialFingerprints.PSObject.Properties['primaryLocationLineHash']) 'SARIF uses distinct target/check fingerprints without claiming a line hash'
    $page = $loc.artifactLocation.uri
    $original = Get-Content $page -Raw
    Set-Content $page -Value "`n$original" -NoNewline
    $findings | ConvertTo-GHComplianceSarif -OutputFile moved.sarif 6>$null
    $moved = (Get-Content moved.sarif -Raw | ConvertFrom-Json).runs[0].results |
        Where-Object { $_.ruleId -eq 'repo.secret-scanning' -and $_.properties.target -eq 'org-a/web' }
    Assert-That ($moved.locations[0].physicalLocation.region.startLine -eq ($loc.region.startLine + 1) -and
        $moved.partialFingerprints.'gheComplianceTargetCheck/v1' -eq $fingerprint) 'SARIF target/check fingerprint remains stable when the line moves'
    Set-Content $page -Value $original -NoNewline
    ConvertTo-GHComplianceSarif -FindingsFile findings.json -OutputFile file-input.sarif `
        -EnterpriseApiUrl 'https://api.github.com' 6>$null
    $fileResult = (Get-Content file-input.sarif -Raw | ConvertFrom-Json).runs[0].results |
        Where-Object { $_.ruleId -eq 'enterprise.max-owners' }
    Assert-That ($fileResult.message.text -match '"max":3' -and
        $fileResult.message.text.Contains('https://github.com/enterprises/contoso')) 'SARIF preserves policy parameters and github.com links from findings JSON'
    $legacy = Get-Content findings.json -Raw | ConvertFrom-Json
    foreach ($target in $legacy) {
        foreach ($failure in $target.failures) {
            $failure.PSObject.Properties.Remove('policyParameters')
        }
    }
    $legacy | ConvertTo-GHComplianceSarif -OutputFile legacy.sarif -EnterpriseApiUrl 'https://api.other.example' 6>$null
    $legacyResult = (Get-Content legacy.sarif -Raw | ConvertFrom-Json).runs[0].results |
        Where-Object { $_.ruleId -eq 'enterprise.max-owners' }
    Assert-That ($legacyResult.message.text -match 'Expected:' -and
        $legacyResult.message.text -notmatch 'Configured policy parameters|Affected resource:') 'Older findings and unrecognized enterprise hosts do not produce invented links or parameters'
    $output = Sync-GHComplianceIssue -FindingsFile findings.json -Repository contoso/github-docs -Token 'fake' -DryRun -MaxNewIssues 3 -WarningAction SilentlyContinue 6>&1 | Out-String
    Assert-That ($output -match 'created: 3' -and $output -match '\[dry-run\] Create') 'Issue sync dry run respects MaxNewIssues'

    $oldOrganization = $env:GHE_ORGANIZATION
    try {
        $env:GHE_ORGANIZATION = 'org-a'
        Import-Module Pester -MinimumVersion 5.7.1 -MaximumVersion 5.99
        $standalone = Invoke-Pester -Path @(
            (Join-Path $root 'tests/enterprise.2fa-required/enterprise.2fa-required.Tests.ps1'),
            (Join-Path $root 'tests/org.2fa-required/org.2fa-required.Tests.ps1')
        ) -PassThru -Output None
        Assert-That ($standalone.PassedCount -eq 1 -and $standalone.FailedCount -eq 1 -and $standalone.SkippedCount -eq 0) 'Individual Pester checks use the existing App connection'
    } finally {
        $env:GHE_ORGANIZATION = $oldOrganization
    }

    Disconnect-GHGovernance
    Assert-That ($null -eq (& $module { $script:AppPrivateKey })) 'Disconnect clears the private key'
    $disconnectedTest = Invoke-Pester -Path (Join-Path $root 'tests/enterprise.2fa-required/enterprise.2fa-required.Tests.ps1') -PassThru -Output None
    Assert-That ($disconnectedTest.FailedCount -eq 1 -and $disconnectedTest.Failed[0].ErrorRecord.Exception.Message -match 'Connect-GHGovernance') 'Individual Pester checks require an existing connection'
    $global:GHESmokePat = $true
    Connect-GHGovernance -Enterprise contoso -Token 'fixture-pat' | Out-Null
    $patRejected = $false
    try {
        Test-GHCompliance -UsePester -DataPath docs/enterprise/_data -PolicyPath compliance/policy.json 6>$null | Out-Null
    } catch {
        $patRejected = $_.Exception.Message -match 'require a GitHub App connection'
    }
    Assert-That $patRejected 'Live Pester checks reject PAT authentication'
    Disconnect-GHGovernance
} catch {
    $script:failures.Add("Unhandled: $($_.Exception.Message) at $($_.InvocationInfo.PositionMessage)")
    Write-Host "  [FAIL] $($_.Exception.Message)`n$($_.InvocationInfo.PositionMessage)`n$($_.ScriptStackTrace)" -ForegroundColor Red
} finally {
    Remove-Variable GHESmokeCalls, GHESmokeErrorPath, GHESmokePat -Scope Global -ErrorAction SilentlyContinue
    Pop-Location
    Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
if ($script:failures.Count) {
    Write-Host "$($script:failures.Count) assertion(s) failed." -ForegroundColor Red; exit 1
}
Write-Host 'All smoke tests passed.' -ForegroundColor Green
