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

function Get-GHJsonProperties {
    param($InputObject)
    if ($InputObject -is [System.Collections.IDictionary]) {
        return , @($InputObject.Keys | ForEach-Object {
                [pscustomobject]@{ Name = [string]$_; Value = $InputObject[$_] }
            })
    }
    if ($InputObject -is [pscustomobject]) {
        return , @($InputObject.PSObject.Properties | Where-Object MemberType -eq 'NoteProperty')
    }
    return , @()
}

function Test-GHJsonSchemaNode {
    param(
        $InputObject,
        $Schema,
        [string] $Path,
        [System.Collections.Generic.List[string]] $Errors,
        [switch] $AllowMissingRequired
    )

    $type = Get-Prop $Schema 'type'
    $validType = switch ($type) {
        'object' { $InputObject -is [pscustomobject] -or $InputObject -is [System.Collections.IDictionary] }
        'array' { $InputObject -is [array] }
        'string' { $InputObject -is [string] }
        'boolean' { $InputObject -is [bool] }
        'integer' {
            $InputObject -is [ValueType] -and $InputObject -isnot [bool] -and
            $InputObject -isnot [char] -and [double]$InputObject -eq [math]::Truncate([double]$InputObject)
        }
        'number' { $InputObject -is [ValueType] -and $InputObject -isnot [bool] -and $InputObject -isnot [char] }
        default { $true }
    }
    if (-not $validType) {
        $Errors.Add("$Path must be of type $type.")
        return
    }

    $enum = Get-Prop $Schema 'enum'
    if ($null -ne $enum -and -not (@($enum) -ccontains $InputObject)) {
        $Errors.Add("$Path must be one of: $(@($enum) -join ', ').")
    }
    $pattern = Get-Prop $Schema 'pattern'
    if ($pattern -and $InputObject -is [string] -and $InputObject -cnotmatch $pattern) {
        $Errors.Add("$Path does not match the required pattern.")
    }
    foreach ($constraint in @(@('minimum', 'ge'), @('maximum', 'le'), @('minLength', 'len-ge'), @('minItems', 'count-ge'))) {
        $limit = Get-Prop $Schema $constraint[0]
        if ($null -eq $limit) { continue }
        $violated = switch ($constraint[1]) {
            'ge' { $InputObject -is [ValueType] -and $InputObject -lt $limit }
            'le' { $InputObject -is [ValueType] -and $InputObject -gt $limit }
            'len-ge' { $InputObject -is [string] -and $InputObject.Length -lt $limit }
            'count-ge' { ($InputObject -is [array]) -and $InputObject.Count -lt $limit }
        }
        if ($violated) { $Errors.Add("$Path does not satisfy $($constraint[0]) = $limit.") }
    }

    if ($type -eq 'object' -or ($null -eq $type -and ($InputObject -is [pscustomobject] -or $InputObject -is [System.Collections.IDictionary]))) {
        $properties = Get-GHJsonProperties $InputObject
        $schemaProperties = Get-Prop $Schema 'properties'
        if (-not $AllowMissingRequired) {
            $requiredNames = Get-Prop $Schema 'required'
            foreach ($requiredName in @($requiredNames)) {
                if ($null -ne $requiredName -and -not ($properties | Where-Object { $_.Name -ceq $requiredName })) {
                    $Errors.Add("$Path.$requiredName is required.")
                }
            }
        }
        foreach ($property in $properties) {
            $propertySchema = if ($schemaProperties) {
                $schemaProperties.PSObject.Properties[[string]$property.Name]
            }
            if ($propertySchema) {
                Test-GHJsonSchemaNode -InputObject $property.Value -Schema $propertySchema.Value `
                    -Path "$Path.$($property.Name)" -Errors $Errors -AllowMissingRequired:$AllowMissingRequired
                continue
            }
            $additional = Get-Prop $Schema 'additionalProperties'
            if ($additional -ceq $false) {
                $Errors.Add("$Path.$($property.Name) is not allowed.")
            } elseif ($additional -is [pscustomobject] -or $additional -is [System.Collections.IDictionary]) {
                Test-GHJsonSchemaNode -InputObject $property.Value -Schema $additional `
                    -Path "$Path.$($property.Name)" -Errors $Errors -AllowMissingRequired:$AllowMissingRequired
            }
        }
        $namePattern = Get-Prop (Get-Prop $Schema 'propertyNames') 'pattern'
        if ($namePattern) {
            foreach ($property in $properties) {
                if ($property.Name -cnotmatch $namePattern) {
                    $Errors.Add("$Path property name '$($property.Name)' does not match the required pattern.")
                }
            }
        }
    } elseif ($type -eq 'array') {
        $itemSchema = Get-Prop $Schema 'items'
        if ($itemSchema) {
            for ($index = 0; $index -lt $InputObject.Count; $index++) {
                Test-GHJsonSchemaNode -InputObject $InputObject[$index] -Schema $itemSchema `
                    -Path "$Path[$index]" -Errors $Errors -AllowMissingRequired:$AllowMissingRequired
            }
        }
        if ((Get-Prop $Schema 'uniqueItems') -ceq $true) {
            $serialized = @($InputObject | ForEach-Object { ConvertTo-Json -InputObject $_ -Depth 20 -Compress })
            if (@($serialized | Select-Object -Unique).Count -ne $serialized.Count) {
                $Errors.Add("$Path must contain unique items.")
            }
        }
    }
}

function Assert-GHJsonSchema {
    param($InputObject, [string] $SchemaName, [string] $DocumentName)

    $schemaPath = Join-Path $PSScriptRoot "../../../schemas/$SchemaName"
    try {
        $schema = Get-Content -LiteralPath $schemaPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    } catch {
        throw "Could not read JSON schema $schemaPath`: $($_.Exception.Message)"
    }
    $errors = [System.Collections.Generic.List[string]]::new()
    Test-GHJsonSchemaNode -InputObject $InputObject -Schema $schema -Path '$' -Errors $errors
    if ($errors.Count -gt 0) {
        throw "$DocumentName is invalid: $($errors -join ' ')"
    }
}

function Get-GHParameterSchema {
    param($Manifest, [string] $CheckId)

    $schema = Get-Prop $Manifest 'parameters'
    if ($null -eq $schema) {
        return [pscustomobject]@{
            type = 'object'
            properties = [pscustomobject]@{}
            additionalProperties = $false
        }
    }
    if ((Get-Prop $schema 'type') -ne 'object' -or
        (Get-Prop $schema 'additionalProperties') -cne $false -or
        $null -eq (Get-Prop $schema 'properties')) {
        throw "Compliance manifest '$CheckId' has an invalid parameters schema."
    }
    $supportedKeywords = @('type', 'properties', 'required', 'additionalProperties')
    foreach ($keyword in (Get-GHJsonProperties $schema)) {
        if ($keyword.Name -notin $supportedKeywords) {
            throw "Compliance manifest '$CheckId' uses unsupported parameter schema keyword '$($keyword.Name)'."
        }
    }
    $parameterProperties = Get-Prop $schema 'properties'
    foreach ($parameter in (Get-GHJsonProperties $parameterProperties)) {
        $parameterSchema = $parameter.Value
        $schemaKeywords = @('type', 'enum', 'minimum', 'maximum', 'minLength', 'minItems', 'items')
        foreach ($keyword in (Get-GHJsonProperties $parameterSchema)) {
            if ($keyword.Name -notin $schemaKeywords) {
                throw "Compliance manifest '$CheckId' uses unsupported parameter schema keyword '$($keyword.Name)' for '$($parameter.Name)'."
            }
        }
        if ((Get-Prop $parameterSchema 'type') -notin @('string', 'integer', 'number', 'boolean', 'array')) {
            throw "Compliance manifest '$CheckId' has an invalid parameter type for '$($parameter.Name)'."
        }
        if ((Get-Prop $parameterSchema 'type') -eq 'array' -and -not (Get-Prop $parameterSchema 'items')) {
            throw "Compliance manifest '$CheckId' must define item constraints for array parameter '$($parameter.Name)'."
        }
    }
    $requiredNames = Get-Prop $schema 'required'
    foreach ($requiredName in @($requiredNames)) {
        if ($null -ne $requiredName -and -not $parameterProperties.PSObject.Properties[$requiredName]) {
            throw "Compliance manifest '$CheckId' requires undeclared parameter '$requiredName'."
        }
    }
    return $schema
}

function Assert-GHCheckParameters {
    param($Parameters, $Schema, [string] $DocumentName, [switch] $AllowMissingRequired)

    if ($null -eq $Parameters) {
        $Parameters = [pscustomobject]@{}
    }
    $errors = [System.Collections.Generic.List[string]]::new()
    Test-GHJsonSchemaNode -InputObject $Parameters -Schema $Schema -Path '$.params' `
        -Errors $errors -AllowMissingRequired:$AllowMissingRequired
    if ($errors.Count -gt 0) {
        throw "$DocumentName has invalid parameters: $($errors -join ' ')"
    }
}

function Assert-GHObjectProperties {
    param($InputObject, [string[]] $Allowed, [string] $DocumentName)
    foreach ($property in (Get-GHJsonProperties $InputObject)) {
        if ($property.Name -notin $Allowed) {
            throw "$DocumentName contains unsupported property '$($property.Name)'."
        }
    }
}

function Assert-GHCompliancePolicy {
    param($Policy, $Checks)

    Assert-GHJsonSchema -InputObject $Policy -SchemaName 'compliance-policy.schema.json' -DocumentName 'Central compliance policy'
    $known = @($Checks.enterprise.Keys) + @($Checks.org.Keys) + @($Checks.repo.Keys)
    foreach ($entry in (Get-GHJsonProperties (Get-Prop $Policy 'checks'))) {
        if ($entry.Name -notin $known) {
            throw "Unknown compliance check in central policy: $($entry.Name)"
        }
        $definition = $Checks.enterprise[$entry.Name]
        if (-not $definition) { $definition = $Checks.org[$entry.Name] }
        if (-not $definition) { $definition = $Checks.repo[$entry.Name] }
        Assert-GHJsonSchema -InputObject $entry.Value -SchemaName 'check-override.schema.json' -DocumentName "Central policy check '$($entry.Name)'"
        Assert-GHCheckParameters -Parameters (Get-Prop $entry.Value 'params') -Schema $definition.ParameterSchema `
            -DocumentName "Central policy check '$($entry.Name)'" -AllowMissingRequired
    }
    foreach ($exemption in (Get-GHJsonProperties (Get-Prop $Policy 'exemptions'))) {
        $targetScope = if ($exemption.Name.StartsWith('enterprise:')) {
            'enterprise'
        } elseif ($exemption.Name.Contains('/')) {
            'repo'
        } else {
            'org'
        }
        foreach ($id in $exemption.Value) {
            if ($id -notin $known) {
                throw "Exemption '$($exemption.Name)' references unknown check '$id'."
            }
            $checkScope = if ($Checks.enterprise.Contains($id)) { 'enterprise' } elseif ($Checks.org.Contains($id)) { 'org' } else { 'repo' }
            if ($targetScope -ne $checkScope) {
                throw "Exemption '$($exemption.Name)' cannot reference $checkScope check '$id'."
            }
        }
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
        Assert-GHJsonSchema -InputObject $manifest -SchemaName 'check-manifest.schema.json' -DocumentName "Compliance manifest $manifestPath"
        $manifestId = Get-Prop $manifest 'id'
        $scope = Get-Prop $manifest 'scope'
        $title = Get-Prop $manifest 'title'
        $remediation = Get-Prop $manifest 'remediation'
        $dataSource = Get-Prop $manifest 'dataSource'
        $sourceType = Get-Prop $dataSource 'type'
        if ($manifestId -ne $id -or $id -notmatch '^[a-z0-9]+(?:[.-][a-z0-9]+)*$') {
            throw "Compliance manifest $manifestPath must have an id matching its folder name."
        }
        $parameterSchema = Get-GHParameterSchema -Manifest $manifest -CheckId $id
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
                Assert-GHObjectProperties $dataSource @('type', 'fields') "Data source for '$id'"
                if ($scope -ne 'enterprise' -or [string]::IsNullOrWhiteSpace((Get-Prop $dataSource 'fields'))) {
                    throw "Compliance check '$id' has an invalid enterprise-owner-info data source."
                }
            }
            'enterprise-actions-permissions' {
                if ($scope -ne 'enterprise' -or (Get-GHJsonProperties $dataSource).Count -ne 1) {
                    throw "Compliance check '$id' has an invalid enterprise-actions-permissions data source."
                }
            }
            'organization-section' {
                Assert-GHObjectProperties $dataSource @('type', 'section') "Data source for '$id'"
                if ($scope -ne 'org' -or (Get-Prop $dataSource 'section') -notin @('settings', 'actionsPermissions', 'actionsWorkflowPermissions', 'webhooks', 'admins', 'rulesets', 'securityConfigDefaults', 'installations', 'actionsSecrets', 'runnerGroups')) {
                    throw "Compliance check '$id' has an invalid organization-section data source."
                }
            }
            'repository' {
                Assert-GHObjectProperties $dataSource @('type', 'codeOwners', 'gitAttributes', 'gitIgnore', 'readme') "Data source for '$id'"
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
                if ($scope -ne 'repo' -or (Get-GHJsonProperties $dataSource).Count -ne 1) {
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
        Assert-GHJsonSchema -InputObject $localPolicy -SchemaName 'check-policy.schema.json' -DocumentName "Compliance policy $policyPath"
        Assert-GHCheckParameters -Parameters (Get-Prop $localPolicy 'params') -Schema $parameterSchema -DocumentName "Compliance policy $policyPath"

        $checks[$scope][$id] = [pscustomobject]@{
            Id = $id
            Scope = [string]$scope
            Title = [string]$title
            Remediation = [string]$remediation
            DataSource = $dataSource
            Path = $testPath
            LocalPolicy = $localPolicy
            ParameterSchema = $parameterSchema
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
            Assert-GHJsonSchema -InputObject $effective -SchemaName 'check-policy.schema.json' -DocumentName "Merged policy check '$id'"
            Assert-GHCheckParameters -Parameters $effective.params -Schema $definition.ParameterSchema -DocumentName "Merged policy check '$id'"
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
