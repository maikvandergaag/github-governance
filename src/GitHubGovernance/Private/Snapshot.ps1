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
    runners = @{ Path = 'orgs/{0}/actions/runners'; Paginate = $true; ItemProperty = 'runners' }
    runnerGroups = @{ Path = 'orgs/{0}/actions/runner-groups'; Paginate = $true; ItemProperty = 'runner_groups' }
    installations = @{ Path = 'orgs/{0}/installations'; Paginate = $true; ItemProperty = 'installations' }
    copilot = @{ Path = 'orgs/{0}/copilot/billing' }
    webhooks = @{ Path = 'orgs/{0}/hooks'; Paginate = $true }
    actionsSecrets = @{ Path = 'orgs/{0}/actions/secrets'; Paginate = $true; ItemProperty = 'secrets' }
    actionsVariables = @{ Path = 'orgs/{0}/actions/variables'; Paginate = $true; ItemProperty = 'variables' }
    securityConfigs = @{ Path = 'orgs/{0}/code-security/configurations'; Paginate = $true }
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
