function New-PersonalMarkdown {
    param([Parameter(Mandatory)] $Snap)
    $titles = [ordered]@{ 'README.md' = 'Overview'; 'repositories.md' = 'Repositories' }
    if ($null -ne $Snap.codeOwners) {
        $titles['codeowners.md'] = 'Code owners'
    }
    $pages = [ordered]@{}
    foreach ($file in $titles.Keys) {
        $nav = New-NavLine -Pages $titles -Current $file `
            -Extra '[Overview](../../README.md) · [Configuration handbook](../../../configuration/README.md)'
        $pages[$file] = New-DocPage -Title "$($Snap.login): $($titles[$file])" -Nav $nav
    }
    $pages['README.md'].Add('Personal account repository inventory and compliance documentation.')
    $pages['README.md'].Add('')
    $md = $pages['repositories.md']
    if ($null -eq $Snap.repositories) {
        $md.Add('_Repository inventory skipped._')
    } elseif (-not $Snap.repositories.Ok) {
        $md.Add((Format-Unavailable $Snap.repositories))
    } else {
        $md.Add((ConvertTo-MdTable -InputObject @($Snap.repositories.Data | Sort-Object name) -Columns ([ordered]@{
                    'Repository' = { $_.name }
                    'Visibility' = { $_.visibility }
                    'Archived' = { $_.archived }
                    'Default branch' = { $_.default_branch }
                    'Secret scanning' = { Get-Prop $_ 'security_and_analysis.secret_scanning.status' }
                    'Push protection' = { Get-Prop $_ 'security_and_analysis.secret_scanning_push_protection.status' }
                    'Last push' = { $_.pushed_at }
                })))
    }
    if ($null -ne $Snap.codeOwners) {
        Add-CodeOwnersContent -Markdown $pages['codeowners.md'] -Snap $Snap
    }
    return Complete-DocPages -Pages $pages
}

function New-OrganizationMarkdown {
    param([Parameter(Mandatory)] $Snap)

    $org = $Snap.login
    # One folder per organization; one page per topic.
    $titles = [ordered]@{
        'README.md' = 'Overview'
        'rulesets.md' = 'Rulesets'
        'security.md' = 'Security & governance'
        'actions.md' = 'Actions'
        'integrations.md' = 'Apps & Copilot'
        'repositories.md' = 'Repositories'
    }
    if ($null -ne $Snap.codeOwners) {
        $titles['codeowners.md'] = 'Code owners'
    }
    $pages = [ordered]@{}
    foreach ($file in $titles.Keys) {
        $nav = New-NavLine -Pages $titles -Current $file `
            -Extra '[Overview](../../README.md) · [Configuration handbook](../../../configuration/README.md)'
        $pages[$file] = New-DocPage -Title "${org}: $($titles[$file])" -Nav $nav
    }

    # --- General settings
    $md = $pages['README.md']
    $md.Add('## General settings')
    $md.Add('')
    if ($Snap.settings.Ok) {
        $s = $Snap.settings.Data
        $md.Add((ConvertTo-MdKeyValue ([ordered]@{
                        'Display name' = Get-Prop $s 'name'
                        'Description' = Get-Prop $s 'description'
                        'Created' = Get-Prop $s 'created_at'
                        '2FA required' = Get-Prop $s 'two_factor_requirement_enabled'
                        'Default repository permission' = Get-Prop $s 'default_repository_permission'
                        'Members can create repositories' = Get-Prop $s 'members_can_create_repositories'
                        'Members can create public repos' = Get-Prop $s 'members_can_create_public_repositories'
                        'Members can create private repos' = Get-Prop $s 'members_can_create_private_repositories'
                        'Members can fork private repos' = Get-Prop $s 'members_can_fork_private_repositories'
                        'Web commit sign-off required' = Get-Prop $s 'web_commit_signoff_required'
                        'Dependabot alerts for new repos' = Get-Prop $s 'dependabot_alerts_enabled_for_new_repositories'
                        'Secret scanning for new repos' = Get-Prop $s 'secret_scanning_enabled_for_new_repositories'
                        'Push protection for new repos' = Get-Prop $s 'secret_scanning_push_protection_enabled_for_new_repositories'
                    })))
    } else {
        $md.Add((Format-Unavailable $Snap.settings))
    }
    $md.Add('')

    # --- People
    $md.Add('## People')
    $md.Add('')
    $memberCount = if ($Snap.members.Ok) {
        $Snap.members.Data.Count
    } else {
        'n/a'
    }
    $collabCount = if ($Snap.outsideCollaborators.Ok) {
        $Snap.outsideCollaborators.Data.Count
    } else {
        'n/a'
    }
    $md.Add("- Members: **$memberCount**")
    $md.Add("- Outside collaborators: **$collabCount**")
    if ($Snap.admins.Ok) {
        $adminList = ($Snap.admins.Data | Sort-Object login | ForEach-Object { "``$($_.login)``" }) -join ', '
        $md.Add("- Organization owners ($($Snap.admins.Data.Count)): $adminList")
    }
    $md.Add('')

    # --- Teams
    $md.Add('## Teams')
    $md.Add('')
    if ($Snap.teams.Ok) {
        $md.Add((ConvertTo-MdTable -InputObject @($Snap.teams.Data | Sort-Object slug) -Columns ([ordered]@{
                        'Team' = { $_.name }
                        'Slug' = { $_.slug }
                        'Privacy' = { $_.privacy }
                        'Parent' = { Get-Prop $_ 'parent.slug' }
                        'Description' = { $_.description }
                    })))
    } else {
        $md.Add((Format-Unavailable $Snap.teams))
    }
    $md.Add('')

    # --- Rulesets
    $md = $pages['rulesets.md']
    $md.Add('## Organization rulesets')
    $md.Add('')
    if ($Snap.rulesets.Ok) {
        $md.Add((ConvertTo-MdTable -InputObject @($Snap.rulesets.Data | Sort-Object name) -Columns ([ordered]@{
                        'Name' = { $_.name }
                        'Target' = { $_.target }
                        'Enforcement' = { $_.enforcement }
                        'Source' = { "$($_.source_type): $($_.source)" }
                    })))
        Add-RulesetDetails -Markdown $md -Rulesets @($Snap.rulesetDetails)
    } else {
        $md.Add((Format-Unavailable $Snap.rulesets))
    }
    $md.Add('')

    # --- Security configurations
    $md = $pages['security.md']
    $md.Add('## Code security configurations')
    $md.Add('')
    if ($Snap.securityConfigs.Ok) {
        $md.Add((ConvertTo-MdTable -InputObject @($Snap.securityConfigs.Data | Sort-Object name) -Columns ([ordered]@{
                        'Name' = { $_.name }
                        'Type' = { Get-Prop $_ 'target_type' }
                        'Advanced Security' = { Get-Prop $_ 'advanced_security' }
                        'Dependabot alerts' = { Get-Prop $_ 'dependabot_alerts' }
                        'Code scanning' = { Get-Prop $_ 'code_scanning_default_setup' }
                        'Secret scanning' = { Get-Prop $_ 'secret_scanning' }
                        'Push protection' = { Get-Prop $_ 'secret_scanning_push_protection' }
                        'Enforcement' = { Get-Prop $_ 'enforcement' }
                    })))
    } else {
        $md.Add((Format-Unavailable $Snap.securityConfigs))
    }
    $md.Add('')

    # --- Custom properties
    $md.Add('## Custom properties')
    $md.Add('')
    if ($Snap.customProperties.Ok) {
        $md.Add((ConvertTo-MdTable -InputObject @($Snap.customProperties.Data | Sort-Object property_name) -Columns ([ordered]@{
                        'Property' = { $_.property_name }
                        'Type' = { $_.value_type }
                        'Required' = { Get-Prop $_ 'required' }
                        'Default' = { (@(Get-Prop $_ 'default_value') -join ', ') }
                        'Allowed values' = { (@(Get-Prop $_ 'allowed_values') -join ', ') }
                        'Description' = { Get-Prop $_ 'description' }
                    })))
    } else {
        $md.Add((Format-Unavailable $Snap.customProperties))
    }
    $md.Add('')

    # --- Custom repository roles
    $md.Add('## Custom repository roles')
    $md.Add('')
    if ($Snap.customRepoRoles.Ok) {
        $roles = @(Get-Prop $Snap.customRepoRoles.Data 'custom_roles')
        $md.Add((ConvertTo-MdTable -InputObject @($roles | Where-Object { $_ } | Sort-Object name) -Columns ([ordered]@{
                        'Role' = { $_.name }
                        'Base role' = { $_.base_role }
                        'Permissions' = { (@($_.permissions) | Sort-Object) -join ', ' }
                        'Description' = { $_.description }
                    })))
    } else {
        $md.Add((Format-Unavailable $Snap.customRepoRoles))
    }
    $md.Add('')

    # --- Webhooks
    $md.Add('## Organization webhooks')
    $md.Add('')
    if ($Snap.webhooks.Ok) {
        $md.Add((ConvertTo-MdTable -InputObject @($Snap.webhooks.Data | Sort-Object { Get-Prop $_ 'config.url' }) -Columns ([ordered]@{
                        'URL' = { Get-Prop $_ 'config.url' }
                        'Active' = { $_.active }
                        'Events' = { (@($_.events) | Sort-Object) -join ', ' }
                        'Content type' = { Get-Prop $_ 'config.content_type' }
                        'TLS verify' = { if ((Get-Prop $_ 'config.insecure_ssl') -eq '1') {
                                'DISABLED'
                            } else {
                                'Yes'
                            } }
                    })))
    } else {
        $md.Add((Format-Unavailable $Snap.webhooks))
    }
    $md.Add('')

    # --- Actions
    $md = $pages['actions.md']
    $md.Add('## GitHub Actions')
    $md.Add('')
    if ($Snap.actionsPermissions.Ok) {
        $a = $Snap.actionsPermissions.Data
        $md.Add((ConvertTo-MdKeyValue ([ordered]@{
                        'Enabled repositories' = Get-Prop $a 'enabled_repositories'
                        'Allowed actions' = Get-Prop $a 'allowed_actions'
                    })))
    } else {
        $md.Add((Format-Unavailable $Snap.actionsPermissions))
    }
    $md.Add('')
    $md.Add('### Runner groups')
    $md.Add('')
    if ($Snap.runnerGroups.Ok) {
        $md.Add((ConvertTo-MdTable -InputObject @($Snap.runnerGroups.Data | Sort-Object name) -Columns ([ordered]@{
                        'Name' = { $_.name }
                        'Visibility' = { $_.visibility }
                        'Inherited' = { $_.inherited }
                        'Allows public repos' = { $_.allows_public_repositories }
                        'Restricted workflows' = { $_.restricted_to_workflows }
                    })))
    } else {
        $md.Add((Format-Unavailable $Snap.runnerGroups))
    }
    $md.Add('')
    $md.Add('### Self-hosted runners')
    $md.Add('')
    if ($Snap.runners.Ok) {
        $md.Add((ConvertTo-MdTable -InputObject @($Snap.runners.Data | Sort-Object name) -Columns ([ordered]@{
                        'Name' = { $_.name }
                        'OS' = { $_.os }
                        'Status' = { $_.status }
                        'Labels' = { ($_.labels | ForEach-Object name) -join ', ' }
                    })))
    } else {
        $md.Add((Format-Unavailable $Snap.runners))
    }
    $md.Add('')
    $md.Add('### Organization secrets (names only)')
    $md.Add('')
    if ($Snap.actionsSecrets.Ok) {
        $md.Add((ConvertTo-MdTable -InputObject @($Snap.actionsSecrets.Data | Sort-Object name) -Columns ([ordered]@{
                        'Name' = { $_.name }
                        'Visibility' = { $_.visibility }
                        'Updated' = { $_.updated_at }
                    })))
    } else {
        $md.Add((Format-Unavailable $Snap.actionsSecrets))
    }
    $md.Add('')
    $md.Add('### Organization variables (names only)')
    $md.Add('')
    if ($Snap.actionsVariables.Ok) {
        $md.Add((ConvertTo-MdTable -InputObject @($Snap.actionsVariables.Data | Sort-Object name) -Columns ([ordered]@{
                        'Name' = { $_.name }
                        'Visibility' = { $_.visibility }
                        'Updated' = { $_.updated_at }
                    })))
    } else {
        $md.Add((Format-Unavailable $Snap.actionsVariables))
    }
    $md.Add('')

    # --- Apps
    $md = $pages['integrations.md']
    $md.Add('## Installed GitHub Apps')
    $md.Add('')
    if ($Snap.installations.Ok) {
        $md.Add((ConvertTo-MdTable -InputObject @($Snap.installations.Data | Sort-Object app_slug) -Columns ([ordered]@{
                        'App' = { $_.app_slug }
                        'Repository selection' = { $_.repository_selection }
                        'Permissions' = {
                            $p = $_.permissions
                            if ($p) {
                                ($p.PSObject.Properties | Sort-Object Name | ForEach-Object { "$($_.Name):$($_.Value)" }) -join ', '
                            }
                        }
                        'Installed' = { $_.created_at }
                    })))
    } else {
        $md.Add((Format-Unavailable $Snap.installations))
    }
    $md.Add('')

    # --- Copilot
    $md.Add('## GitHub Copilot')
    $md.Add('')
    if ($Snap.copilot.Ok) {
        $c = $Snap.copilot.Data
        $md.Add((ConvertTo-MdKeyValue ([ordered]@{
                        'Plan type' = Get-Prop $c 'plan_type'
                        'Seat management' = Get-Prop $c 'seat_management_setting'
                        'Total seats' = Get-Prop $c 'seat_breakdown.total'
                        'Active this cycle' = Get-Prop $c 'seat_breakdown.active_this_cycle'
                        'Inactive this cycle' = Get-Prop $c 'seat_breakdown.inactive_this_cycle'
                        'Public code suggestions' = Get-Prop $c 'public_code_suggestions'
                        'IDE chat' = Get-Prop $c 'ide_chat'
                        'Platform chat' = Get-Prop $c 'platform_chat'
                        'CLI' = Get-Prop $c 'cli'
                    })))
    } else {
        $md.Add((Format-Unavailable $Snap.copilot))
    }
    $md.Add('')

    # --- Repositories
    $md = $pages['repositories.md']
    $md.Add('## Repositories')
    $md.Add('')
    if ($null -eq $Snap.repositories) {
        $md.Add('_Skipped (-SkipRepositories)._')
    } elseif ($Snap.repositories.Ok) {
        $repos = @($Snap.repositories.Data | Sort-Object name)
        $active = @($repos | Where-Object { -not $_.archived })
        $md.Add("Total: **$($repos.Count)** (active: $($active.Count), archived: $($repos.Count - $active.Count))")
        $md.Add('')
        $md.Add((ConvertTo-MdTable -InputObject $repos -Columns ([ordered]@{
                        'Repository' = { $_.name }
                        'Visibility' = { $_.visibility }
                        'Archived' = { $_.archived }
                        'Default branch' = { $_.default_branch }
                        'Language' = { $_.language }
                        'GHAS' = { Get-Prop $_ 'security_and_analysis.advanced_security.status' }
                        'Secret scanning' = { Get-Prop $_ 'security_and_analysis.secret_scanning.status' }
                        'Push protection' = { Get-Prop $_ 'security_and_analysis.secret_scanning_push_protection.status' }
                        'Last push' = { $_.pushed_at }
                    })))
    } else {
        $md.Add((Format-Unavailable $Snap.repositories))
    }
    $md.Add('')

    # --- Code owners summary (full rules live in codeowners.md)
    $md.Add('## Code owners')
    $md.Add('')
    if ($null -eq $Snap.codeOwners) {
        $md.Add('_Skipped (-SkipRepositories / -SkipCodeOwners, or repository list unavailable)._')
    } else {
        $co = @($Snap.codeOwners)
        $with = @($co | Where-Object { (Get-Prop $_ 'pathEvaluated') -and $_.path })
        $withErrors = @($with | Where-Object { (Get-Prop $_ 'errorsEvaluated') -and @($_.errors).Count -gt 0 })
        $unknown = @($co | Where-Object { -not (Get-Prop $_ 'pathEvaluated') }).Count
        $md.Add("Evaluated repositories with CODEOWNERS: **$($with.Count) / $($co.Count - $unknown)**, with errors: **$($withErrors.Count)**. Full rules: [codeowners.md](codeowners.md)")
        if ($unknown -gt 0) {
            $md.Add("CODEOWNERS locations not evaluated: **$unknown**.")
        }
        $md.Add('')
        $md.Add((ConvertTo-MdTable -InputObject @($co | Sort-Object repository) -Columns ([ordered]@{
                        'Repository' = { $_.repository }
                        'CODEOWNERS' = { if (-not (Get-Prop $_ 'pathEvaluated')) {
                                'Not evaluated'
                            } elseif ($_.path) {
                                $_.path
                            } else {
                                '**missing**'
                            } }
                        'Rules' = { if (Get-Prop $_ 'pathEvaluated') {
                                @($_.rules).Count
                            } else {
                                'n/a'
                            } }
                        'Owners' = { (@($_.rules | ForEach-Object { $_.owners }) | Sort-Object -Unique) -join ', ' }
                        'Errors' = { if (Get-Prop $_ 'errorsEvaluated') {
                                @($_.errors).Count
                            } else {
                                'n/a'
                            } }
                    })))
    }

    if ($null -ne $Snap.codeOwners) {
        Add-CodeOwnersContent -Markdown $pages['codeowners.md'] -Snap $Snap
    }
    return Complete-DocPages -Pages $pages
}

function Add-CodeOwnersContent {
    param($Markdown, [Parameter(Mandatory)] $Snap)

    $co = @($Snap.codeOwners)
    $md = $Markdown

    # --- Owner -> repositories (who owns what)
    $md.Add('## By owner')
    $md.Add('')
    $byOwner = foreach ($repo in $co) {
        foreach ($rule in @($repo.rules)) {
            foreach ($owner in @($rule.owners)) {
                [pscustomobject]@{ owner = $owner; repository = $repo.repository; pattern = $rule.pattern }
            }
        }
    }
    $ownerRows = @($byOwner | Group-Object owner | Sort-Object Name | ForEach-Object {
            [pscustomobject]@{
                owner = $_.Name
                repositories = ($_.Group | ForEach-Object repository | Sort-Object -Unique) -join ', '
                rules = $_.Count
            }
        })
    $md.Add((ConvertTo-MdTable -InputObject $ownerRows -Columns ([ordered]@{
                    'Owner' = { $_.owner }
                    'Rules' = { $_.rules }
                    'Repositories' = { $_.repositories }
                })))
    $md.Add('')

    # --- Repositories without CODEOWNERS
    $missing = @($co | Where-Object { (Get-Prop $_ 'pathEvaluated') -and -not $_.path } | ForEach-Object repository | Sort-Object)
    $md.Add('## Repositories without CODEOWNERS')
    $md.Add('')
    $md.Add($(if ($missing.Count) {
                ($missing | ForEach-Object { "- $_" }) -join "`n"
            } else {
                '_None._'
            }))
    $md.Add('')

    # --- Per repository rules + validation errors
    $md.Add('## By repository')
    foreach ($repo in @($co | Where-Object { (Get-Prop $_ 'pathEvaluated') -and $_.path } | Sort-Object repository)) {
        $md.Add('')
        $md.Add("### $($repo.repository)")
        $md.Add('')
        $md.Add("File: ``$($repo.path)``")
        $md.Add('')
        $md.Add((ConvertTo-MdTable -InputObject @($repo.rules) -Columns ([ordered]@{
                        'Line' = { $_.line }
                        'Pattern' = { "``$($_.pattern)``" }
                        'Owners' = { if (@($_.owners).Count) {
                                @($_.owners) -join ', '
                            } else {
                                '_(no owner: unowned)_'
                            } }
                    })))
        if (-not (Get-Prop $repo 'errorsEvaluated')) {
            $md.Add('')
            $md.Add('_Validation errors not available._')
        } elseif (@($repo.errors).Count -gt 0) {
            $md.Add('')
            $md.Add('**Validation errors:**')
            $md.Add('')
            $md.Add((ConvertTo-MdTable -InputObject @($repo.errors) -Columns ([ordered]@{
                            'Line' = { Get-Prop $_ 'line' }
                            'Kind' = { Get-Prop $_ 'kind' }
                            'Message' = { Get-Prop $_ 'message' }
                        })))
        }
    }
}

function New-EnterpriseConfigMarkdown {
    param(
        [Parameter(Mandatory)] $EnterpriseInfo,
        [Parameter(Mandatory)] $Snap
    )

    $titles = [ordered]@{
        'README.md' = 'Policies & access'
        'rulesets.md' = 'Rulesets'
        'actions.md' = 'Actions'
        'security.md' = 'Code security & audit'
    }
    $pages = [ordered]@{}
    foreach ($file in $titles.Keys) {
        $nav = New-NavLine -Pages $titles -Current $file `
            -Extra '[Enterprise overview](../README.md) · [Configuration handbook](../../configuration/README.md)'
        $pages[$file] = New-DocPage -Title "Enterprise $($EnterpriseInfo.Name): $($titles[$file])" -Nav $nav
    }

    $g = $Snap.graph.Data
    $o = Get-Prop $g 'ownerInfo'

    # --- Overview
    $md = $pages['README.md']
    $md.Add('## Overview')
    $md.Add('')
    if ($Snap.graph.Ok) {
        $md.Add((ConvertTo-MdKeyValue ([ordered]@{
                        'Enterprise members' = Get-Prop $g 'members.totalCount'
                        'Licenses (total)' = Get-Prop $g 'billingInfo.totalLicenses'
                        'Licenses (available)' = Get-Prop $g 'billingInfo.totalAvailableLicenses'
                        'Licensable users' = Get-Prop $g 'billingInfo.allLicensableUsersCount'
                        'Outside collaborators (all)' = Get-Prop $o 'outsideCollaborators.totalCount'
                    })))
    } else {
        $md.Add((Format-Unavailable $Snap.graph))
    }
    $md.Add('')

    # --- Policies
    $md.Add('## Organization and repository policies')
    $md.Add('')
    if ($o) {
        $md.Add('Values other than "No policy" are enforced for all organizations in the enterprise.')
        $md.Add('')
        $md.Add((ConvertTo-MdKeyValue ([ordered]@{
                        'Base repository permission' = Format-PolicyValue (Get-Prop $o 'defaultRepositoryPermissionSetting')
                        'Repository creation' = Format-PolicyValue (Get-Prop $o 'membersCanCreateRepositoriesSetting')
                        'Members can create public repos' = Get-Prop $o 'membersCanCreatePublicRepositoriesSetting'
                        'Members can create private repos' = Get-Prop $o 'membersCanCreatePrivateRepositoriesSetting'
                        'Members can create internal repos' = Get-Prop $o 'membersCanCreateInternalRepositoriesSetting'
                        'Repo admins can change visibility' = Format-PolicyValue (Get-Prop $o 'membersCanChangeRepositoryVisibilitySetting')
                        'Repo admins can delete/transfer repos' = Format-PolicyValue (Get-Prop $o 'membersCanDeleteRepositoriesSetting')
                        'Repo admins can delete issues' = Format-PolicyValue (Get-Prop $o 'membersCanDeleteIssuesSetting')
                        'Members can invite outside collaborators' = Format-PolicyValue (Get-Prop $o 'membersCanInviteCollaboratorsSetting')
                        'Repo admins can update protected branches' = Format-PolicyValue (Get-Prop $o 'membersCanUpdateProtectedBranchesSetting')
                        'Private repository forking' = Format-PolicyValue (Get-Prop $o 'allowPrivateRepositoryForkingSetting')
                        'Deploy keys' = Format-PolicyValue (Get-Prop $o 'repositoryDeployKeySetting')
                    })))
    } else {
        $md.Add('_Not available. The token needs enterprise owner rights (read:enterprise / admin:enterprise)._')
    }
    $md.Add('')

    # --- Authentication and access
    $md.Add('## Authentication and access')
    $md.Add('')
    if ($o) {
        $md.Add((ConvertTo-MdKeyValue ([ordered]@{
                        '2FA required' = Format-PolicyValue (Get-Prop $o 'twoFactorRequiredSetting')
                        '2FA disallowed methods' = Format-PolicyValue (Get-Prop $o 'twoFactorDisallowedMethodsSetting')
                        'Affiliated users without 2FA' = Get-Prop $o 'affiliatedUsersWithTwoFactorDisabledExist'
                        'SAML IdP issuer' = Get-Prop $o 'samlIdentityProvider.issuer'
                        'SAML SSO URL' = Get-Prop $o 'samlIdentityProvider.ssoUrl'
                        'OIDC provider' = Get-Prop $o 'oidcProvider.providerType'
                        'IP allow list' = Format-PolicyValue (Get-Prop $o 'ipAllowListEnabledSetting')
                        'IP allow list for installed apps' = Format-PolicyValue (Get-Prop $o 'ipAllowListForInstalledAppsEnabledSetting')
                    })))
        $entries = @(Get-Prop $o 'ipAllowListEntries.nodes' | Where-Object { $_ })
        if ($entries.Count -gt 0) {
            $md.Add('')
            $md.Add("### IP allow list entries ($(Get-Prop $o 'ipAllowListEntries.totalCount'))")
            $md.Add('')
            $md.Add((ConvertTo-MdTable -InputObject @($entries | Sort-Object allowListValue) -Columns ([ordered]@{
                            'Range' = { $_.allowListValue }
                            'Name' = { $_.name }
                            'Active' = { $_.isActive }
                        })))
        }
    } else {
        $md.Add('_Not available. The token needs enterprise owner rights._')
    }
    $md.Add('')

    # --- Owners
    $md.Add('## Enterprise owners')
    $md.Add('')
    $owners = @(Get-Prop $o 'admins.nodes' | Where-Object { $_ } | ForEach-Object login | Sort-Object)
    if ($o) {
        $md.Add("Owners ($(Get-Prop $o 'admins.totalCount')): " + $(if ($owners) {
                    ($owners | ForEach-Object { "``$_``" }) -join ', '
                } else {
                    '-'
                }))
    } else {
        $md.Add('_Not available._')
    }
    $md.Add('')

    # --- Rulesets
    $md = $pages['rulesets.md']
    $md.Add('## Enterprise rulesets')
    $md.Add('')
    if (-not $Snap.graph.Ok) {
        $md.Add('_Not available._')
    } elseif (@($Snap.rulesetDetails).Count -eq 0) {
        $md.Add('_None._')
    } else {
        $md.Add((ConvertTo-MdTable -InputObject @($Snap.rulesetDetails | Sort-Object name) -Columns ([ordered]@{
                        'Name' = { $_.name }
                        'Target' = { $_.target }
                        'Enforcement' = { $_.enforcement }
                    })))
        Add-RulesetDetails -Markdown $md -Rulesets @($Snap.rulesetDetails)
    }
    $md.Add('')

    # --- Actions
    $md = $pages['actions.md']
    $md.Add('## GitHub Actions')
    $md.Add('')
    if ($Snap.actionsPermissions.Ok) {
        $md.Add((ConvertTo-MdKeyValue ([ordered]@{
                        'Enabled organizations' = Get-Prop $Snap.actionsPermissions.Data 'enabled_organizations'
                        'Allowed actions' = Get-Prop $Snap.actionsPermissions.Data 'allowed_actions'
                    })))
    } else {
        $md.Add((Format-Unavailable $Snap.actionsPermissions))
    }
    $md.Add('')
    $md.Add('### Enterprise runner groups')
    $md.Add('')
    if ($Snap.runnerGroups.Ok) {
        $md.Add((ConvertTo-MdTable -InputObject @($Snap.runnerGroups.Data | Sort-Object name) -Columns ([ordered]@{
                        'Name' = { $_.name }
                        'Visibility' = { Get-Prop $_ 'visibility' }
                        'Allows public repos' = { Get-Prop $_ 'allows_public_repositories' }
                        'Restricted workflows' = { Get-Prop $_ 'restricted_to_workflows' }
                    })))
    } else {
        $md.Add((Format-Unavailable $Snap.runnerGroups))
    }
    $md.Add('')
    $md.Add('### Enterprise self-hosted runners')
    $md.Add('')
    if ($Snap.runners.Ok) {
        $md.Add((ConvertTo-MdTable -InputObject @($Snap.runners.Data | Sort-Object name) -Columns ([ordered]@{
                        'Name' = { $_.name }
                        'OS' = { $_.os }
                        'Status' = { $_.status }
                        'Labels' = { (@($_.labels) | ForEach-Object name) -join ', ' }
                    })))
    } else {
        $md.Add((Format-Unavailable $Snap.runners))
    }
    $md.Add('')

    # --- Code security configurations
    $md = $pages['security.md']
    $md.Add('## Enterprise code security configurations')
    $md.Add('')
    if ($Snap.securityConfigs.Ok) {
        $md.Add((ConvertTo-MdTable -InputObject @($Snap.securityConfigs.Data | Sort-Object name) -Columns ([ordered]@{
                        'Name' = { $_.name }
                        'Advanced Security' = { Get-Prop $_ 'advanced_security' }
                        'Dependabot alerts' = { Get-Prop $_ 'dependabot_alerts' }
                        'Code scanning' = { Get-Prop $_ 'code_scanning_default_setup' }
                        'Secret scanning' = { Get-Prop $_ 'secret_scanning' }
                        'Push protection' = { Get-Prop $_ 'secret_scanning_push_protection' }
                        'Enforcement' = { Get-Prop $_ 'enforcement' }
                    })))
    } else {
        $md.Add((Format-Unavailable $Snap.securityConfigs))
    }
    $md.Add('')

    # --- Custom properties
    $md.Add('## Enterprise custom properties')
    $md.Add('')
    if ($Snap.customProperties.Ok) {
        $md.Add((ConvertTo-MdTable -InputObject @($Snap.customProperties.Data | Where-Object { $_ } | Sort-Object property_name) -Columns ([ordered]@{
                        'Property' = { $_.property_name }
                        'Type' = { $_.value_type }
                        'Required' = { Get-Prop $_ 'required' }
                        'Allowed values' = { (@(Get-Prop $_ 'allowed_values') -join ', ') }
                    })))
    } else {
        $md.Add((Format-Unavailable $Snap.customProperties))
    }
    $md.Add('')

    # --- Audit log streaming
    $md.Add('## Audit log streaming')
    $md.Add('')
    if ($Snap.auditLogStreams.Ok) {
        $md.Add((ConvertTo-MdTable -InputObject @($Snap.auditLogStreams.Data | Where-Object { $_ }) -Columns ([ordered]@{
                        'Type' = { Get-Prop $_ 'stream_type' }
                        'Enabled' = { Get-Prop $_ 'enabled' }
                        'Created' = { Get-Prop $_ 'created_at' }
                    })))
    } else {
        $md.Add((Format-Unavailable $Snap.auditLogStreams))
    }
    $md.Add('')

    # --- Not automated
    $md = $pages['README.md']
    $md.Add('## Not collected by this script')
    $md.Add('')
    $md.Add('Verify these enterprise settings manually or document them separately:')
    $md.Add('')
    $md.Add('- Copilot policies and model availability at enterprise level')
    $md.Add('- Personal access token policies (classic/fine-grained restrictions, lifetimes)')
    $md.Add('- GitHub App and OAuth app policies')
    $md.Add('- SCIM provisioning details and team sync (Enterprise Managed Users)')
    $md.Add('- Audit log settings other than streaming (e.g. IP disclosure, retention)')
    $md.Add('- Credential inventory (Settings > Authentication security > Credentials export)')
    return Complete-DocPages -Pages $pages
}

function New-EnterpriseMarkdown {
    param(
        [Parameter(Mandatory)] $EnterpriseInfo,
        [Parameter(Mandatory)] $EnterpriseSnap,
        [Parameter(Mandatory)] [object[]] $Snapshots,
        [string[]] $MissingInstallations = @()
    )

    $o = Get-Prop $EnterpriseSnap.graph.Data 'ownerInfo'
    $md = [System.Collections.Generic.List[string]]::new()
    $md.Add("# GitHub Enterprise: $($EnterpriseInfo.Name)")
    $md.Add('')
    $md.Add((ConvertTo-MdKeyValue ([ordered]@{
                    'Slug' = $EnterpriseInfo.Slug
                    'Created' = $EnterpriseInfo.CreatedAt
                    'API endpoint' = $script:ApiBaseUrl
                    'Organizations' = $Snapshots.Count
                    'Enterprise owners' = Get-Prop $o 'admins.totalCount'
                    '2FA required' = Format-PolicyValue (Get-Prop $o 'twoFactorRequiredSetting')
                    'Identity provider' = $(if (Get-Prop $o 'oidcProvider') {
                            "OIDC ($(Get-Prop $o 'oidcProvider.providerType'))"
                        } elseif (Get-Prop $o 'samlIdentityProvider') {
                            'SAML'
                        } elseif ($o) {
                            'None'
                        } else {
                            $null
                        })
                    'Documentation updated' = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd HH:mm') + ' UTC'
                })))
    $md.Add('')
    $md.Add('Enterprise configuration: [Policies & access](enterprise/README.md) · [Rulesets](enterprise/rulesets.md) · [Actions](enterprise/actions.md) · [Code security & audit](enterprise/security.md)')
    $md.Add('')
    $md.Add('Compliance: [findings report](compliance/README.md)')
    $md.Add('')
    $md.Add('Configuration: [Configuration handbook](../configuration/README.md)')
    $md.Add('')
    if ($MissingInstallations.Count -gt 0) {
        $md.Add('> [!WARNING]')
        $list = ($MissingInstallations | ForEach-Object { '`' + $_ + '`' }) -join ', '
        $md.Add("> The documentation GitHub App is not installed on: $list. Those sections are incomplete.")
        $md.Add('')
    }

    $md.Add('## Organizations')
    $md.Add('')
    $md.Add((ConvertTo-MdTable -InputObject $Snapshots -Columns ([ordered]@{
                    'Organization' = { "[$($_.login)](organizations/$($_.login)/README.md)" }
                    '2FA required' = { Get-Prop $_.settings.Data 'two_factor_requirement_enabled' }
                    'Members' = { if ($_.members.Ok) {
                            $_.members.Data.Count
                        } else {
                            'n/a'
                        } }
                    'Outside collab.' = { if ($_.outsideCollaborators.Ok) {
                            $_.outsideCollaborators.Data.Count
                        } else {
                            'n/a'
                        } }
                    'Repositories' = { if ($_.repositories -and $_.repositories.Ok) {
                            $_.repositories.Data.Count
                        } else {
                            'n/a'
                        } }
                    'Rulesets' = { if ($_.rulesets.Ok) {
                            $_.rulesets.Data.Count
                        } else {
                            'n/a'
                        } }
                    'CODEOWNERS' = {
                        if ($null -eq $_.codeOwners) {
                            'n/a'
                        } else {
                            $known = @($_.codeOwners | Where-Object { Get-Prop $_ 'pathEvaluated' })
                            $unknown = @($_.codeOwners).Count - $known.Count
                            "$(@($known | Where-Object path).Count)/$($known.Count)" + $(if ($unknown) {
                                    " ($unknown not evaluated)"
                                })
                        }
                    }
                    'Webhooks' = { if ($_.webhooks.Ok) {
                            $_.webhooks.Data.Count
                        } else {
                            'n/a'
                        } }
                    'Org secrets' = { if ($_.actionsSecrets.Ok) {
                            $_.actionsSecrets.Data.Count
                        } else {
                            'n/a'
                        } }
                    'Copilot seats' = { if ($_.copilot.Ok) {
                            Get-Prop $_.copilot.Data 'seat_breakdown.total'
                        } else {
                            'n/a'
                        } }
                })))
    $md.Add('')
    $md.Add('---')
    $md.Add('_Generated by Export-GitHubEnterpriseDocs.ps1. Do not edit manually; changes are overwritten on the next run._')

    return ($md -join "`n") + "`n"
}
