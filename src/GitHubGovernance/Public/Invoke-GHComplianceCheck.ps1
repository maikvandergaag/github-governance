function Invoke-GHComplianceCheck {
    <#
    .SYNOPSIS
        Evaluates one compliance check against live GitHub data.
    .DESCRIPTION
        Requires an existing GitHub App connection. Uses the local check policy unless Config is
        supplied by the compliance runner. Returns pass, fail or na (not evaluated).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $CheckId,
        [string] $Organization,
        [string] $Repository,
        $Config,
        [string] $TestsPath = (Join-Path $PSScriptRoot '../../../tests')
    )

    Assert-GHConnection
    if ($script:AuthMode -ne 'App') {
        throw 'Compliance tests require a GitHub App connection. Run Connect-GHGovernance with -AppClientId and -AppPrivateKey.'
    }

    $checks = Get-GHComplianceChecks -TestsPath $TestsPath
    $definition = $null
    foreach ($scope in @('enterprise', 'org', 'repo')) {
        if ($checks[$scope].Contains($CheckId)) {
            $definition = $checks[$scope][$CheckId]
            break
        }
    }
    if (-not $definition) {
        throw "Unknown compliance check: $CheckId"
    }
    $scope = $definition.Scope
    if ($scope -eq 'enterprise' -and $script:Connection.Scope -ne 'enterprise') {
        throw 'Enterprise checks require an enterprise connection.'
    }
    if ($scope -eq 'org' -and $script:Connection.Scope -eq 'user') {
        throw 'Organization checks do not apply to a personal account.'
    }
    if ($scope -ne 'enterprise' -and [string]::IsNullOrWhiteSpace($Organization)) {
        throw "Organization is required for $CheckId."
    }
    if ($scope -eq 'repo' -and [string]::IsNullOrWhiteSpace($Repository)) {
        throw "Repository is required for $CheckId."
    }

    if ($null -eq $Config) {
        $Config = $definition.LocalPolicy
    }
    $enabled = Get-Prop $Config 'enabled'
    if ($enabled -isnot [bool]) {
        throw "Policy for $CheckId must specify a boolean enabled value."
    }
    if (-not $enabled) {
        return NotEvaluated 'The check is disabled in this policy.'
    }
    $check = Get-CompliancePolicyCheck -Id $CheckId -TestsPath $TestsPath -Cache @{}
    $params = Get-Prop $Config 'params'
    $installation = if ($scope -eq 'enterprise') {
        'enterprise'
    } else {
        "org:$Organization"
    }
    if (-not (Get-RequestHeaders -Scope $installation)) {
        return NotEvaluated 'The GitHub App installation or token is not accessible.'
    }
    $org = if ($Organization) {
        [uri]::EscapeDataString($Organization)
    } else {
        ''
    }
    $repo = if ($Repository) {
        [uri]::EscapeDataString($Repository)
    } else {
        ''
    }
    $dataSource = $definition.DataSource

    switch ($dataSource.type) {
        'enterprise-owner-info' {
            $query = 'query($slug: String!) { enterprise(slug: $slug) { ownerInfo { ' + $dataSource.fields + ' } } }'
            $script:LastGraphQLErrorPaths = @()
            try {
                $data = Invoke-GitHubGraphQL -Query $query -Variables @{ slug = $script:Connection.Enterprise } -AllowPartial
            } catch {
                $response = $_.Exception.PSObject.Properties['Response']
                $status = if ($response -and $response.Value) {
                    [int]$response.Value.StatusCode
                } else {
                    $null
                }
                if ($status -in 403, 404) {
                    return NotEvaluated "Enterprise GraphQL request is not accessible (HTTP $status)."
                }
                throw
            }
            $snap = [pscustomobject]@{
                graph = [pscustomobject]@{
                    Ok = $true
                    Data = (Get-Prop $data 'enterprise')
                    ErrorPaths = @($script:LastGraphQLErrorPaths)
                }
            }
            return & $check $snap $params
        }
        'enterprise-actions-permissions' {
            $slug = [uri]::EscapeDataString($script:Connection.Enterprise)
            $section = Invoke-GitHubRest -Path "enterprises/$slug/actions/permissions" -StrictErrors
            $snap = [pscustomobject]@{ actionsPermissions = $section }
            return & $check $snap $params
        }
        'organization-section' {
            $sectionName = $dataSource.section
            $paths = @{
                settings = "orgs/$org"
                actionsPermissions = "orgs/$org/actions/permissions"
                webhooks = "orgs/$org/hooks"
                admins = "orgs/$org/members?role=admin"
                rulesets = "orgs/$org/rulesets"
            }
            $section = Invoke-GitHubRest -Path $paths[$sectionName] `
                -Paginate:($sectionName -in 'webhooks', 'admins', 'rulesets') -StrictErrors
            $snap = [pscustomobject]@{ $sectionName = $section }
            if ($sectionName -eq 'rulesets') {
                $details = @()
                if ($section.Ok) {
                    foreach ($ruleset in @($section.Data)) {
                        $detail = Invoke-GitHubRest -Path "orgs/$org/rulesets/$($ruleset.id)" -StrictErrors
                        if (-not $detail.Ok) {
                            return NotEvaluated "Organization ruleset details are not accessible (HTTP $($detail.Status))."
                        }
                        $details += $detail.Data
                    }
                }
                $snap | Add-Member -NotePropertyName rulesetDetails -NotePropertyValue $details
                $snap | Add-Member -NotePropertyName rulesetDetailsComplete -NotePropertyValue $section.Ok
            }
            return & $check $snap $params
        }
        'repository' {
            $repositoryResult = Invoke-GitHubRest -Path "repos/$org/$repo" -StrictErrors
            if (-not $repositoryResult.Ok) {
                return NotEvaluated "Repository is not accessible (HTTP $($repositoryResult.Status))."
            }
            $repoData = $repositoryResult.Data
            if (Get-Prop $repoData 'archived') {
                return NotEvaluated 'Archived repositories are excluded.'
            }
            $owners = $null
            $codeOwnersCheck = Get-Prop $dataSource 'codeOwners'
            if ($codeOwnersCheck) {
                $query = @'
query($owner: String!, $name: String!) {
  repository(owner: $owner, name: $name) {
    github: object(expression: "HEAD:.github/CODEOWNERS") { ... on Blob { text } }
    root: object(expression: "HEAD:CODEOWNERS") { ... on Blob { text } }
    docs: object(expression: "HEAD:docs/CODEOWNERS") { ... on Blob { text } }
  }
}
'@
                $script:LastGraphQLErrorPaths = @()
                try {
                    $data = Invoke-GitHubGraphQL -Query $query -Variables @{ owner = $Organization; name = $Repository } -Scope $installation -AllowPartial
                } catch {
                    $response = $_.Exception.PSObject.Properties['Response']
                    $status = if ($response -and $response.Value) {
                        [int]$response.Value.StatusCode
                    } else {
                        $null
                    }
                    if ($status -in 403, 404) {
                        return NotEvaluated "CODEOWNERS data is not accessible (HTTP $status)."
                    }
                    throw
                }
                if (@($script:LastGraphQLErrorPaths).Count -gt 0) {
                    return NotEvaluated 'CODEOWNERS data is not accessible.'
                }
                $data = Get-Prop $data 'repository'
                if (-not $data) {
                    return NotEvaluated 'Repository CODEOWNERS data was not returned.'
                }
                foreach ($locationName in 'github', 'root', 'docs') {
                    if (-not $data.PSObject.Properties[$locationName]) {
                        return NotEvaluated 'CODEOWNERS locations were not fully returned.'
                    }
                }
                $location = $null
                foreach ($entry in @(@('github', '.github/CODEOWNERS'), @('root', 'CODEOWNERS'), @('docs', 'docs/CODEOWNERS'))) {
                    if ($null -ne (Get-Prop $data "$($entry[0]).text")) {
                        $location = $entry[1]
                        break
                    }
                }
                $errors = @()
                if ($location -and $codeOwnersCheck -eq 'valid') {
                    $result = Invoke-GitHubRest -Path "repos/$org/$repo/codeowners/errors" -StrictErrors
                    if (-not $result.Ok) {
                        return NotEvaluated "CODEOWNERS validation is not accessible (HTTP $($result.Status))."
                    }
                    if (-not $result.Data -or -not $result.Data.PSObject.Properties['errors'] -or
                        $null -eq $result.Data.PSObject.Properties['errors'].Value) {
                        return NotEvaluated 'CODEOWNERS validation errors were not returned.'
                    }
                    $errors = @(Get-Prop $result.Data 'errors' | Where-Object { $_ })
                }
                $owners = [pscustomobject]@{
                    path = $location
                    pathEvaluated = $true
                    errors = $errors
                    errorsEvaluated = ($codeOwnersCheck -eq 'valid' -and [bool]$location)
                }
            }
            return & $check $repoData $null $owners $params
        }
        default {
            throw "Unsupported live data source '$($dataSource.type)' for $CheckId."
        }
    }
}
