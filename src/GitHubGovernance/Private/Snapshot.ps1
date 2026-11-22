# Section definitions shared by the focused getters (Get-GHOrganization*) and the full snapshots.
# Path: '{0}' = organization login or enterprise slug. Paginate/ItemProperty: see Invoke-GitHubRest.
$script:OrgSections = [ordered]@{
    settings = @{ Path = 'orgs/{0}' }
    teams = @{ Path = 'orgs/{0}/teams'; Paginate = $true }
    members = @{ Path = 'orgs/{0}/members'; Paginate = $true }
    admins = @{ Path = 'orgs/{0}/members?role=admin'; Paginate = $true }
    outsideCollaborators = @{ Path = 'orgs/{0}/outside_collaborators'; Paginate = $true }
    rulesets = @{ Path = 'orgs/{0}/rulesets'; Paginate = $true }
    actionsPermissions = @{ Path = 'orgs/{0}/actions/permissions' }
    actionsWorkflowPermissions = @{ Path = 'orgs/{0}/actions/permissions/workflow' }
    runners = @{ Path = 'orgs/{0}/actions/runners'; Paginate = $true; ItemProperty = 'runners' }
    runnerGroups = @{ Path = 'orgs/{0}/actions/runner-groups'; Paginate = $true; ItemProperty = 'runner_groups' }
    installations = @{ Path = 'orgs/{0}/installations'; Paginate = $true; ItemProperty = 'installations' }
    copilot = @{ Path = 'orgs/{0}/copilot/billing' }
    webhooks = @{ Path = 'orgs/{0}/hooks'; Paginate = $true }
    actionsSecrets = @{ Path = 'orgs/{0}/actions/secrets'; Paginate = $true; ItemProperty = 'secrets' }
    actionsVariables = @{ Path = 'orgs/{0}/actions/variables'; Paginate = $true; ItemProperty = 'variables' }
    securityConfigs = @{ Path = 'orgs/{0}/code-security/configurations'; Paginate = $true }
    securityConfigDefaults = @{ Path = 'orgs/{0}/code-security/configurations/defaults'; Paginate = $true }
    customProperties = @{ Path = 'orgs/{0}/properties/schema' }
    customRepoRoles = @{ Path = 'orgs/{0}/custom-repository-roles' }
}

$script:EnterpriseSections = [ordered]@{
    actionsPermissions = @{ Path = 'enterprises/{0}/actions/permissions' }
    runnerGroups = @{ Path = 'enterprises/{0}/actions/runner-groups'; Paginate = $true; ItemProperty = 'runner_groups' }
    runners = @{ Path = 'enterprises/{0}/actions/runners'; Paginate = $true; ItemProperty = 'runners' }
    securityConfigs = @{ Path = 'enterprises/{0}/code-security/configurations'; Paginate = $true }
    customProperties = @{ Path = 'enterprises/{0}/properties/schema' }
    auditLogStreams = @{ Path = 'enterprises/{0}/audit-log/streams' }
}

function Get-OrgSection {
    # Fetches one organization section as an Ok/Status/Data result. Values are never persisted:
    # variable values and webhook secrets are stripped here, before any caller sees them.
    param([Parameter(Mandatory)] [string] $Org, [Parameter(Mandatory)] [string] $Name)
    $def = $script:OrgSections[$Name]
    $result = Invoke-GitHubRest -Path ($def.Path -f $Org) -Paginate:([bool]$def['Paginate']) -ItemProperty ([string]$def['ItemProperty'])
    if ($result.Ok -and $Name -eq 'actionsVariables') {
        $result.Data = @($result.Data | Select-Object -ExcludeProperty value)
    }
    if ($result.Ok -and $Name -eq 'webhooks') {
        foreach ($hook in @($result.Data)) {
            if ($hook -and $hook.PSObject.Properties['config'] -and $hook.config -and $hook.config.PSObject.Properties['secret']) {
                $hook.config.PSObject.Properties.Remove('secret')
            }
        }
    }
    return $result
}

function Get-EnterpriseSection {
    param([Parameter(Mandatory)] [string] $Name)
    $def = $script:EnterpriseSections[$Name]
    return Invoke-GitHubRest -Path ($def.Path -f $script:Connection.Enterprise) -Paginate:([bool]$def['Paginate']) -ItemProperty ([string]$def['ItemProperty'])
}

function Get-GHRootFileEvidence {
    param([string] $Organization, [string] $Repository, [string] $DefaultBranch, [switch] $StrictErrors)
    if ([string]::IsNullOrWhiteSpace($DefaultBranch)) {
        return $null
    }
    $branch = [uri]::EscapeDataString($DefaultBranch)
    try {
        $result = Invoke-GitHubRest "repos/$Organization/$Repository/git/trees/$branch" -StrictErrors:$StrictErrors
    } catch {
        if (-not $_.Exception.PSObject.Properties['Response'] -or -not $_.Exception.Response -or
            [int]$_.Exception.Response.StatusCode -ne 409) {
            throw
        }
        Write-Verbose "Root tree unavailable for $Organization/$Repository (HTTP 409); repository may be empty."
        $result = [pscustomobject]@{ Ok = $false; Status = 409; Data = $null }
    }
    $data = $result.Data
    if (-not $result.Ok -or (Get-Prop $data 'truncated') -cne $false -or
        $null -eq $data -or -not $data.PSObject.Properties['tree'] -or $null -eq $data.tree) {
        return [pscustomobject]@{
            gitAttributes = [pscustomobject]@{ evaluated = $false; present = $null }
            gitIgnore = [pscustomobject]@{ evaluated = $false; present = $null }
            readme = [pscustomobject]@{ evaluated = $false; present = $null }
        }
    }
    $evidence = [ordered]@{}
    foreach ($file in @(@('gitAttributes', '.gitattributes'), @('gitIgnore', '.gitignore'), @('readme', 'README.md'))) {
        $matches = @($data.tree | Where-Object {
                (Get-Prop $_ 'path') -ceq $file[1] -and
                (Get-Prop $_ 'type') -eq 'blob' -and (Get-Prop $_ 'mode') -in @('100644', '100755')
            })
        $evidence[$file[0]] = [pscustomobject]@{ evaluated = $true; present = ($matches.Count -gt 0) }
    }
    return [pscustomobject]$evidence
}

function Get-GHBranchEvidence {
    param([string] $Organization, [string] $Repository, [string] $DefaultBranch, [switch] $StrictErrors)
    if ([string]::IsNullOrWhiteSpace($DefaultBranch)) {
        return $null
    }
    $branch = [uri]::EscapeDataString($DefaultBranch)
    $base = "repos/$Organization/$Repository"
    $rules = Invoke-GitHubRest "$base/rules/branches/$branch" -Paginate -StrictErrors:$StrictErrors
    $protection = Invoke-GitHubRest "$base/branches/$branch/protection" -StrictErrors:$StrictErrors
    if (-not $protection.Ok -and $protection.Status -eq 404) {
        $branchInfo = Invoke-GitHubRest "$base/branches/$branch" -StrictErrors:$StrictErrors
        if ($branchInfo.Ok -and (Get-Prop $branchInfo.Data 'protected') -ceq $false) {
            $protection = [pscustomobject]@{ Ok = $true; Status = 200; Data = $null }
        }
    }
    return [pscustomobject]@{ branch = $DefaultBranch; rules = $rules; protection = $protection }
}

function Get-OrgRulesetDetails {
    # The list endpoint does not return rules/conditions/bypass actors; fetch each ruleset individually.
    param([Parameter(Mandatory)] [string] $Org, $RulesetsResult, [ref] $DetailsComplete)
    if ($DetailsComplete) {
        $DetailsComplete.Value = [bool]$RulesetsResult.Ok
    }
    if (-not $RulesetsResult.Ok) {
        return @()
    }
    return @(foreach ($rs in @($RulesetsResult.Data)) {
            if (-not $rs) {
                continue
            }
            $detail = Invoke-GitHubRest "orgs/$Org/rulesets/$($rs.id)"
            if ($detail.Ok) {
                $detail.Data
            } else {
                if ($DetailsComplete) {
                    $DetailsComplete.Value = $false
                }
                $rs
            }
        })
}

function Get-EnterpriseGraph {
    <#
    .SYNOPSIS
        Enterprise policies, identity, IP allow list, owners and licenses via GraphQL, as an
        Ok/Status/Data/ErrorPaths result. Deliberately never queries secrets such as SAML
        recoveryCodes or idpCertificate.
    #>
    $query = @'
query($slug: String!) {
  enterprise(slug: $slug) {
    members(first: 1) { totalCount }
    billingInfo { totalLicenses totalAvailableLicenses allLicensableUsersCount }
    rulesets(first: 100) { nodes { databaseId name } }
    ownerInfo {
      twoFactorRequiredSetting
      twoFactorDisallowedMethodsSetting
      affiliatedUsersWithTwoFactorDisabledExist
      defaultRepositoryPermissionSetting
      membersCanCreateRepositoriesSetting
      membersCanCreatePublicRepositoriesSetting
      membersCanCreatePrivateRepositoriesSetting
      membersCanCreateInternalRepositoriesSetting
      membersCanChangeRepositoryVisibilitySetting
      membersCanDeleteRepositoriesSetting
      membersCanDeleteIssuesSetting
      membersCanInviteCollaboratorsSetting
      membersCanUpdateProtectedBranchesSetting
      allowPrivateRepositoryForkingSetting
      repositoryDeployKeySetting
      ipAllowListEnabledSetting
      ipAllowListForInstalledAppsEnabledSetting
      ipAllowListEntries(first: 100) { totalCount nodes { name allowListValue isActive } }
      samlIdentityProvider { issuer ssoUrl }
      oidcProvider { providerType tenantId }
      admins(first: 100, role: OWNER) { totalCount nodes { login } }
      outsideCollaborators(first: 1) { totalCount }
    }
  }
}
'@
    $graph = [pscustomobject]@{ Ok = $false; Status = $null; Data = $null; ErrorPaths = @() }
    try {
        $script:LastGraphQLErrorPaths = @()
        $data = Invoke-GitHubGraphQL -Query $query -Variables @{ slug = $script:Connection.Enterprise } -AllowPartial
        if ($data -and $data.enterprise) {
            # ErrorPaths, e.g. "enterprise.ownerInfo.samlIdentityProvider": fields the credential could not read.
            $graph = [pscustomobject]@{ Ok = $true; Status = 200; Data = $data.enterprise; ErrorPaths = @($script:LastGraphQLErrorPaths) }
        }
    } catch {
        Write-Verbose "Enterprise GraphQL query failed: $($_.Exception.Message)"
    }
    return $graph
}

function Get-EnterpriseRulesetDetails {
    # GraphQL lists enterprise rulesets; REST returns them in the same format as org rulesets.
    param($Graph)
    $ids = @(Get-Prop $Graph.Data 'rulesets.nodes' | Where-Object { $_ } | ForEach-Object databaseId)
    return @(foreach ($id in $ids) {
            $detail = Invoke-GitHubRest "enterprises/$($script:Connection.Enterprise)/rulesets/$id"
            if ($detail.Ok) {
                $detail.Data
            }
        })
}
