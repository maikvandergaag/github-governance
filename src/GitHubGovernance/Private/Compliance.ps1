# Compliance check metadata used by Test-GHCompliance.

function Pass {
    @{ status = 'pass' }
}
function Fail([string] $Detail) {
    @{ status = 'fail'; detail = $Detail }
}
function NotEvaluated([string] $Reason) {
    @{ status = 'na'; detail = $Reason }
}

function Test-GHSecurityDefault {
    param($Snap, [string] $Field, [string] $Label)
    $defaults = Get-Section $Snap 'securityConfigDefaults'
    if ($null -eq $defaults) { return NotEvaluated 'Default code security configurations are not accessible.' }
    foreach ($visibility in @('public', 'private_and_internal')) {
        $matches = @($defaults | Where-Object { (Get-Prop $_ 'default_for_new_repos') -in @($visibility, 'all') })
        if ($matches.Count -ne 1) {
            return NotEvaluated "A unique default security configuration for $visibility was not returned."
        }
        $value = Get-Prop $matches[0] "configuration.$Field"
        if ($value -notin @('enabled', 'disabled', 'not_set')) {
            return NotEvaluated "$Label was not returned for $visibility."
        }
        if ($value -ne 'enabled') {
            return Fail "$Label is $value in the default configuration for $visibility repositories."
        }
    }
    Pass
}

function Test-GHBranchRule {
    param($Repo, [string] $RuleType, [scriptblock] $RuleTest, [scriptblock] $ProtectionTest, [string] $Finding)
    $evidence = Get-Prop $Repo 'complianceBranchEvidence'
    if ($null -eq $evidence) { return NotEvaluated 'Default branch protection evidence was not collected.' }
    $rules = Get-Prop $evidence 'rules'
    $protection = Get-Prop $evidence 'protection'
    $unknown = -not (Get-Prop $rules 'Ok') -or -not (Get-Prop $protection 'Ok')
    if (Get-Prop $rules 'Ok') {
        foreach ($rule in @(Get-Prop $rules 'Data' | Where-Object { (Get-Prop $_ 'type') -eq $RuleType })) {
            $result = & $RuleTest $rule
            if ($result -ceq $true) { return Pass }
            if ($result -isnot [bool]) { $unknown = $true }
        }
    }
    if ((Get-Prop $protection 'Ok') -and $null -ne (Get-Prop $protection 'Data')) {
        $result = & $ProtectionTest (Get-Prop $protection 'Data')
        if ($result -ceq $true) { return Pass }
        if ($result -isnot [bool]) { $unknown = $true }
    }
    if ($unknown) { return NotEvaluated 'Branch rules or classic protection could not be fully evaluated.' }
    Fail $Finding
}

function Get-Section {
    # Returns the Data of a snapshot section, or $null when the API call was not successful.
    param($Snap, [string] $Name)
    $section = Get-Prop $Snap $Name
    if ($section -and (Get-Prop $section 'Ok')) {
        return , @(Get-Prop $section 'Data')
    }
    return $null
}

function Get-OwnerInfoField {
    param($Snap, [string] $Field)
    $graph = Get-Prop $Snap 'graph'
    $ownerInfo = Get-Prop $graph 'Data.ownerInfo'
    if (-not (Get-Prop $graph 'Ok') -or $null -eq $ownerInfo) {
        return @{ Readable = $false; Value = $null }
    }
    $root = $Field.Split('.')[0]
    $blocked = @(@(Get-Prop $graph 'ErrorPaths') | Where-Object {
            $_ -and ($_ -eq 'enterprise.ownerInfo' -or $_ -like "enterprise.ownerInfo.$root*")
        })
    if ($blocked.Count -gt 0) {
        return @{ Readable = $false; Value = $null }
    }
    return @{ Readable = $true; Value = (Get-Prop $ownerInfo $Field) }
}

function Test-PolicySetting {
    param($Snap, [string] $Field, [string[]] $Allowed, [string] $Label)
    $f = Get-OwnerInfoField $Snap $Field
    if (-not $f.Readable) {
        return NotEvaluated "$Field not readable (token needs enterprise owner rights)."
    }
    if ($null -eq $f.Value) {
        return NotEvaluated "$Field not returned."
    }
    if ($f.Value -eq 'NO_POLICY') {
        return Fail "$Label is not enforced at enterprise level (organizations decide)."
    }
    if ($f.Value -in $Allowed) {
        Pass
    } else {
        Fail "$Label is ``$($f.Value)`` (allowed: $($Allowed -join ', '))."
    }
}

function Get-CompliancePolicyCheck {
    param([string] $Id, [string] $TestsPath, [hashtable] $Cache)
    if (-not $Cache.ContainsKey($Id)) {
        $path = Join-Path (Join-Path $TestsPath $Id) "$Id.Tests.ps1"
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Compliance check not found: $path"
        }
        $check = & $path -PolicyOnly
        if ($check -isnot [scriptblock]) {
            throw "Compliance check $Id does not define a policy script block."
        }
        $Cache[$Id] = $check
    }
    return $Cache[$Id]
}

function Get-GHComplianceChecks {
    param([Parameter(Mandatory)] [string] $TestsPath)

    if (-not (Test-Path -LiteralPath $TestsPath -PathType Container)) {
        throw "Compliance tests directory not found: $TestsPath"
    }
    $checks = @{
        enterprise = [ordered]@{}
        org = [ordered]@{}
        repo = [ordered]@{}
    }
    foreach ($directory in Get-ChildItem -LiteralPath $TestsPath -Directory | Sort-Object Name) {
        $id = $directory.Name
        $manifestPath = Join-Path $directory.FullName 'check.json'
        if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
            continue
        }

        try {
            $manifest = Get-Content -LiteralPath $manifestPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        } catch {
            throw "Could not read compliance manifest $manifestPath`: $($_.Exception.Message)"
        }
        $manifestId = Get-Prop $manifest 'id'
        $scope = Get-Prop $manifest 'scope'
        $title = Get-Prop $manifest 'title'
        $remediation = Get-Prop $manifest 'remediation'
        $dataSource = Get-Prop $manifest 'dataSource'
        $sourceType = Get-Prop $dataSource 'type'
        if ($manifestId -ne $id -or $id -notmatch '^[a-z0-9]+(?:[.-][a-z0-9]+)*$') {
            throw "Compliance manifest $manifestPath must have an id matching its folder name."
        }
        if ($scope -notin @('enterprise', 'org', 'repo') -or -not $id.StartsWith("$scope.")) {
            throw "Compliance manifest $manifestPath has an invalid scope for '$id'."
        }
        if ([string]::IsNullOrWhiteSpace($title) -or [string]::IsNullOrWhiteSpace($remediation)) {
            throw "Compliance manifest $manifestPath must specify title and remediation."
        }

        $testPath = Join-Path $directory.FullName "$id.Tests.ps1"
        $policyPath = Join-Path $directory.FullName 'policy.json'
        $issuePath = Join-Path $directory.FullName 'issue.md'
        foreach ($requiredPath in @($testPath, $policyPath, $issuePath)) {
            if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
                throw "Compliance check '$id' is missing required file: $requiredPath"
            }
        }

        switch ($sourceType) {
            'enterprise-owner-info' {
                if ($scope -ne 'enterprise' -or [string]::IsNullOrWhiteSpace((Get-Prop $dataSource 'fields'))) {
                    throw "Compliance check '$id' has an invalid enterprise-owner-info data source."
                }
            }
            'enterprise-actions-permissions' {
                if ($scope -ne 'enterprise') {
                    throw "Compliance check '$id' has an invalid enterprise-actions-permissions data source."
                }
            }
            'organization-section' {
                if ($scope -ne 'org' -or (Get-Prop $dataSource 'section') -notin @('settings', 'actionsPermissions', 'actionsWorkflowPermissions', 'webhooks', 'admins', 'rulesets', 'securityConfigDefaults', 'installations', 'actionsSecrets', 'runnerGroups')) {
                    throw "Compliance check '$id' has an invalid organization-section data source."
                }
            }
            'repository' {
                $codeOwners = Get-Prop $dataSource 'codeOwners'
                $gitAttributes = Get-Prop $dataSource 'gitAttributes'
                $gitIgnore = Get-Prop $dataSource 'gitIgnore'
                $readme = Get-Prop $dataSource 'readme'
                if ($scope -ne 'repo' -or ($codeOwners -and $codeOwners -notin @('present', 'valid')) -or
                    ($null -ne $gitAttributes -and $gitAttributes -isnot [bool]) -or
                    ($null -ne $gitIgnore -and $gitIgnore -isnot [bool]) -or
                    ($null -ne $readme -and $readme -isnot [bool])) {
                    throw "Compliance check '$id' has an invalid repository data source."
                }
            }
            'repository-branch-rules' {
                if ($scope -ne 'repo') {
                    throw "Compliance check '$id' has an invalid repository-branch-rules data source."
                }
            }
            default {
                throw "Compliance check '$id' has an unsupported data source type '$sourceType'."
            }
        }

        try {
            $localPolicy = Get-Content -LiteralPath $policyPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        } catch {
            throw "Could not read compliance policy $policyPath`: $($_.Exception.Message)"
        }
        $localEnabled = Get-Prop $localPolicy 'enabled'
        $localSeverity = Get-Prop $localPolicy 'severity'
        if ($localEnabled -isnot [bool] -or $localSeverity -notin @('high', 'medium', 'low')) {
            throw "Compliance policy $policyPath must specify boolean enabled and severity high, medium or low."
        }

        $checks[$scope][$id] = [pscustomobject]@{
            Id = $id
            Scope = [string]$scope
            Title = [string]$title
            Remediation = [string]$remediation
            DataSource = $dataSource
            Path = $testPath
            LocalPolicy = $localPolicy
        }
    }
    return $checks
}

function Merge-GHCompliancePolicy {
    param($Policy, $Checks)

    $effectiveChecks = [pscustomobject]@{}
    foreach ($scope in @('enterprise', 'org', 'repo')) {
        foreach ($id in $Checks[$scope].Keys) {
            $definition = $Checks[$scope][$id]
            $local = $definition.LocalPolicy
            $configured = $Policy.checks.PSObject.Properties[$id]
            $enabled = if ($configured -and $configured.Value.PSObject.Properties['enabled']) {
                $configured.Value.enabled
            } else {
                $local.enabled
            }
            $severity = if ($configured -and $configured.Value.PSObject.Properties['severity']) {
                $configured.Value.severity
            } else {
                $local.severity
            }
            $params = [ordered]@{}
            $localParams = Get-Prop $local 'params'
            $configuredParams = if ($configured) { Get-Prop $configured.Value 'params' }
            foreach ($source in @($localParams, $configuredParams)) {
                if ($source) {
                    foreach ($property in $source.PSObject.Properties) {
                        $params[$property.Name] = $property.Value
                    }
                }
            }
            $effective = [pscustomobject]@{
                enabled = $enabled
                severity = $severity
                params = [pscustomobject]$params
            }
            $effectiveChecks | Add-Member -NotePropertyName $id -NotePropertyValue $effective
        }
    }
    return [pscustomobject]@{
        checks = $effectiveChecks
        exemptions = $Policy.exemptions
    }
}

function Invoke-Checks {
    param(
        [System.Collections.IDictionary] $Checks,
        [object[]] $Arguments,
        [string] $TargetId,
        $Policy,
        [string] $TestsPath,
        [hashtable] $CheckModules
    )

    $failures = [System.Collections.Generic.List[object]]::new()
    $notEvaluated = [System.Collections.Generic.List[object]]::new()
    # Direct property lookups: check ids and repo names contain dots, so Get-Prop (dot-path) can't be used here.
    $exemptProp = if ($Policy.PSObject.Properties['exemptions']) {
        $Policy.exemptions.PSObject.Properties[$TargetId]
    }
    $exempt = if ($exemptProp) {
        @($exemptProp.Value)
    } else {
        @()
    }

    foreach ($id in $Checks.Keys) {
        $configProp = $Policy.checks.PSObject.Properties[$id]
        $config = if ($configProp) {
            $configProp.Value
        } else {
            $null
        }
        if (-not $config -or -not (Get-Prop $config 'enabled')) {
            continue
        }
        if ($id -in $exempt) {
            continue
        }

        $params = Get-Prop $config 'params'
        $check = Get-CompliancePolicyCheck -Id $id -TestsPath $TestsPath -Cache $CheckModules
        $checkArguments = @($Arguments) + @($params)
        try {
            $result = & $check @checkArguments
        } catch {
            throw "Compliance check $id failed for ${TargetId}: $($_.Exception.Message)"
        }

        switch ($result.status) {
            'pass' {
            }
            'fail' {
                $failures.Add([ordered]@{
                        check = $id
                        severity = (Get-Prop $config 'severity') ?? 'medium'
                        title = $Checks[$id].Title
                        detail = $result.detail
                        remediation = $Checks[$id].Remediation
                        policyParameters = $params
                    })
            }
            'na' {
                $notEvaluated.Add([ordered]@{ check = $id; reason = $result.detail })
            }
            'notEvaluated' {
                $notEvaluated.Add([ordered]@{ check = $id; reason = $result.detail })
            }
            default {
                throw "Compliance check $id returned an invalid status for ${TargetId}: $($result.status)"
            }
        }
    }
    return @{ failures = $failures.ToArray(); notEvaluated = $notEvaluated.ToArray() }
}
