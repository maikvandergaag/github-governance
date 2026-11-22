function ConvertTo-GHComplianceSarif {
    <#
    .SYNOPSIS
        Converts compliance findings into a SARIF file, so they show up as code scanning alerts
        in the Security tab of the docs repository.

    .DESCRIPTION
        Each failed check becomes a SARIF result whose location points to the line in the generated
        documentation that shows the offending setting (e.g. the repository row, the 2FA setting or the
        CODEOWNERS section). Each result includes a target-and-check fingerprint; the upload action also
        calculates GitHub's line fingerprint for tracking alerts across runs.

    .EXAMPLE
        Test-GHCompliance | ConvertTo-GHComplianceSarif -OutputFile ./compliance.sarif
    #>
    [CmdletBinding()]
    param(
        # Findings from Test-GHCompliance (pipeline), or a findings JSON file.
        [Parameter(ValueFromPipeline)] [object[]] $Findings,
        [string] $FindingsFile = './compliance-findings.json',
        [string] $OutputFile = './compliance.sarif',
        # Repository root: used to resolve docs paths for line lookups. SARIF paths stay relative to it.
        [string] $RepositoryRoot = '.',
        [string] $ServerUrl = $env:GITHUB_SERVER_URL,
        [string] $Repository = $env:GITHUB_REPOSITORY,
        [string] $Commit = $env:GITHUB_SHA,
        # Use a committed policy file when generated documentation is not published.
        [switch] $UsePolicyLocations,
        [string] $EnterpriseApiUrl = $env:ENTERPRISE_API_URL,
        [string] $TargetServerUrl
    )
    begin {
        $collected = [System.Collections.Generic.List[object]]::new()
    }
    process {
        foreach ($f in @($Findings)) {
            if ($null -ne $f) {
                $collected.Add($f)
            }
        }
    }
    end {
        $Findings = $collected.ToArray()
        # Where each check is visible in the generated docs: page (relative to the target's docs folder) + line regex.
        $CheckAnchors = @{
            # Enterprise (docs/enterprise/enterprise/)
            'enterprise.2fa-required' = @('README.md', '^\| 2FA required \|')
            'enterprise.users-without-2fa' = @('README.md', '^\| Affiliated users without 2FA \|')
            'enterprise.sso-configured' = @('README.md', '^## Authentication and access')
            'enterprise.default-permission-policy' = @('README.md', '^\| Base repository permission \|')
            'enterprise.repo-creation-policy' = @('README.md', '^\| Repository creation \|')
            'enterprise.repo-deletion-restricted' = @('README.md', '^\| Repo admins can delete/transfer repos \|')
            'enterprise.visibility-change-restricted' = @('README.md', '^\| Repo admins can change visibility \|')
            'enterprise.ip-allow-list' = @('README.md', '^\| IP allow list \|')
            'enterprise.max-owners' = @('README.md', '^## Enterprise owners')
            'enterprise.actions-restricted' = @('actions.md', '^\| Allowed actions \|')
            # Organization (docs/enterprise/organizations/<org>/)
            'org.2fa-required' = @('README.md', '^\| 2FA required \|')
            'org.default-permission' = @('README.md', '^\| Default repository permission \|')
            'org.no-public-repo-creation' = @('README.md', '^\| Members can create public repos \|')
            'org.push-protection-new-repos' = @('README.md', '^\| Push protection for new repos \|')
            'org.max-owners' = @('README.md', '^- Organization owners')
            'org.actions-restricted' = @('actions.md', '^\| Allowed actions \|')
            'org.webhooks-tls' = @('security.md', '^## Organization webhooks')
            'org.default-branch-ruleset' = @('rulesets.md', '^## Organization rulesets')
        }

        # SARIF level + GitHub security-severity (0-10) per policy severity.
        $SeverityMap = @{
            high = @{ level = 'error'; score = '8.0' }
            medium = @{ level = 'warning'; score = '5.0' }
            low = @{ level = 'note'; score = '2.0' }
        }

        $Impacts = @{
            'enterprise.2fa-required' = 'Accounts without a second factor are more vulnerable to credential theft.'
            'enterprise.users-without-2fa' = 'Affiliated accounts without 2FA are more vulnerable to credential theft.'
            'enterprise.sso-configured' = 'Without enterprise SSO, central identity and access controls may not apply.'
            'enterprise.default-permission-policy' = 'Unrestricted base permissions can give members broader repository access than intended.'
            'enterprise.repo-creation-policy' = 'Unrestricted repository creation can expose code or data in public repositories.'
            'enterprise.repo-deletion-restricted' = 'Repository deletion or transfer can cause data loss or move assets outside intended control.'
            'enterprise.visibility-change-restricted' = 'Unauthorized visibility changes can expose private code and data.'
            'enterprise.ip-allow-list' = 'Without network restrictions, access is not limited to approved IP ranges.'
            'enterprise.max-owners' = 'Excess enterprise owners increase the number of accounts with broad administrative privileges.'
            'enterprise.actions-restricted' = 'Unapproved actions may execute untrusted code in workflows with repository access.'
            'org.2fa-required' = 'Member accounts without a second factor are more vulnerable to credential theft.'
            'org.default-permission' = 'Broad base permissions can grant members unintended access to repositories.'
            'org.no-public-repo-creation' = 'Public repositories can expose code or data to anyone.'
            'org.push-protection-new-repos' = 'New repositories without push protection may accept committed credentials.'
            'org.actions-restricted' = 'Unapproved actions may execute untrusted code in workflows with repository access.'
            'org.webhooks-tls' = 'Disabling TLS verification can expose webhook payloads to interception or tampering.'
            'org.max-owners' = 'Excess organization owners increase the number of accounts with broad administrative privileges.'
            'org.default-branch-ruleset' = 'Without a pull-request requirement, changes may reach default branches without review.'
            'repo.not-public' = 'Public repositories expose their contents to anyone.'
            'repo.secret-scanning' = 'Leaked credentials may remain undetected without secret scanning.'
            'repo.push-protection' = 'Without push protection, supported secrets may be committed to the repository.'
            'repo.codeowners-present' = 'Without CODEOWNERS, designated owners cannot be automatically requested for review.'
            'repo.codeowners-valid' = 'Invalid CODEOWNERS entries may prevent intended owners from being requested for review.'
            'repo.stale' = 'Unmaintained repositories may retain outdated dependencies, access, or configuration.'
        }

        if (-not $TargetServerUrl -and $EnterpriseApiUrl) {
            $apiUri = [uri]$EnterpriseApiUrl
            if ($apiUri.Scheme -eq 'https' -and $apiUri.Host -eq 'api.github.com') {
                $TargetServerUrl = 'https://github.com'
            } elseif ($apiUri.Scheme -eq 'https' -and $apiUri.Host -match '^api\.[a-z0-9-]+\.ghe\.com$') {
                $TargetServerUrl = "https://$($apiUri.Host.Substring(4))"
            }
        }

        $FileCache = @{}

        function Find-Line {
            <#
            .SYNOPSIS
                Returns the 1-based line number of the first line matching $Pattern (optionally after $After), or 1.
            #>
            param([string] $RelativePath, [string] $Pattern, [string] $After)

            $full = Join-Path $RepositoryRoot $RelativePath
            if (-not $FileCache.ContainsKey($full)) {
                $FileCache[$full] = if (Test-Path $full) {
                    @(Get-Content $full)
                } else {
                    @()
                }
            }
            $lines = $FileCache[$full]
            $start = 0
            if ($After) {
                for ($i = 0; $i -lt $lines.Count; $i++) {
                    if ($lines[$i] -match $After) {
                        $start = $i; break
                    }
                }
            }
            for ($i = $start; $i -lt $lines.Count; $i++) {
                if ($lines[$i] -match $Pattern) {
                    return $i + 1
                }
            }
            return 1
        }

        function Get-Location {
            # Returns @{ path; line } pointing at the most relevant line in the generated docs.
            param($Target, [string] $Check)

            if ($UsePolicyLocations) {
                $path = 'compliance/policy.json'
                return @{ path = $path; line = (Find-Line $path ('"' + [regex]::Escape($Check) + '"\s*:')) }
            }
            $folder = Split-Path $Target.docs -Parent   # enterprise/ or organizations/<org>/
            if ($Target.type -ne 'repo') {
                $anchor = $CheckAnchors[$Check]
                if (-not $anchor) {
                    return @{ path = $Target.docs; line = 1 }
                }
                $page = "$folder/$($anchor[0])"
                return @{ path = $page; line = (Find-Line $page $anchor[1]) }
            }

            $repo = [regex]::Escape($Target.repo)
            if ($Check -like 'repo.codeowners-*') {
                $page = "$folder/codeowners.md"
                $line = if ($Check -eq 'repo.codeowners-present') {
                    Find-Line $page "^- $repo$" -After '^## Repositories without CODEOWNERS'
                } else {
                    Find-Line $page "^### $repo$"
                }
                return @{ path = $page; line = $line }
            }
            $page = "$folder/repositories.md"
            return @{ path = $page; line = (Find-Line $page "^\| $repo \|" -After '^## Repositories') }
        }

        function Get-Fingerprint {
            param([string] $Value)
            $bytes = [System.Security.Cryptography.SHA256]::HashData([System.Text.Encoding]::UTF8.GetBytes($Value))
            return ([System.BitConverter]::ToString($bytes) -replace '-', '').Substring(0, 32).ToLowerInvariant()
        }

        $findings = if ($Findings) {
            @($Findings)
        } else {
            @(Get-Content $FindingsFile -Raw | ConvertFrom-Json -Depth 20)
        }

        $rules = [ordered]@{}
        $results = [System.Collections.Generic.List[object]]::new()

        foreach ($target in $findings) {
            foreach ($f in @($target.failures)) {
                if (-not $f) {
                    continue
                }
                $sev = $SeverityMap[[string]$f.severity] ?? $SeverityMap.medium

                if (-not $rules.Contains($f.check)) {
                    $reference = switch ($target.type) {
                        'enterprise' {
                            'https://docs.github.com/en/enterprise-cloud@latest/admin/enforcing-policies'
                        }
                        'org' {
                            'https://docs.github.com/en/organizations/managing-organization-settings'
                        }
                        default {
                            'https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features'
                        }
                    }
                    if ($f.check -in 'repo.secret-scanning', 'repo.push-protection', 'org.push-protection-new-repos') {
                        $reference = 'https://docs.github.com/en/code-security/secret-scanning'
                    }
                    $impact = $Impacts[$f.check]
                    $helpText = "Requirement: $($f.title).`n"
                    $helpMarkdown = "## Requirement`n`n$($f.title).`n"
                    if ($impact) {
                        $helpText += "`nPotential impact: $impact`n"
                        $helpMarkdown += "`n## Potential impact`n`n$impact`n"
                    }
                    $helpText += "`nRemediation: $($f.remediation)`nVerify the setting and rerun the compliance workflow. Review $reference."
                    $helpMarkdown += "`n## Remediation`n`n1. Review the observed setting and configured policy in the result.`n2. $($f.remediation)`n3. Verify the setting and rerun the compliance workflow.`n`n[GitHub documentation]($reference). Accept a deviation by adding an exemption in ``compliance/policy.json``."
                    $rules[$f.check] = [ordered]@{
                        id = $f.check
                        name = ($f.check -replace '[^a-zA-Z0-9]', ' ' | ForEach-Object { (Get-Culture).TextInfo.ToTitleCase($_) }) -replace ' ', ''
                        shortDescription = @{ text = $f.title }
                        fullDescription = @{ text = "$($f.title). Applies to: $($target.type)." }
                        help = @{ text = $helpText; markdown = $helpMarkdown }
                        defaultConfiguration = @{ level = $sev.level }
                        properties = [ordered]@{
                            tags = @('security', 'compliance', "github-$($target.type)")
                            'security-severity' = $sev.score
                            precision = 'very-high'
                        }
                    }
                }

                $location = Get-Location -Target $target -Check $f.check
                $message = "[$($target.id)] $($f.title): $($f.detail)`nExpected: $($f.title)."
                $policyParameters = if ($f -is [System.Collections.IDictionary]) {
                    if ($f.Contains('policyParameters')) {
                        $f['policyParameters']
                    }
                } else {
                    Get-Prop $f 'policyParameters'
                }
                if ($null -ne $policyParameters) {
                    $message += "`nConfigured policy parameters: $($policyParameters | ConvertTo-Json -Depth 10 -Compress)"
                }
                if ($TargetServerUrl) {
                    $targetPath = switch ($target.type) {
                        'enterprise' {
                            "enterprises/$([uri]::EscapeDataString([string]$target.org))"
                        }
                        'org' {
                            [uri]::EscapeDataString([string]$target.org)
                        }
                        'repo' {
                            "$([uri]::EscapeDataString([string]$target.org))/$([uri]::EscapeDataString([string]$target.repo))"
                        }
                    }
                    if ($targetPath) {
                        $message += "`nAffected resource: $($TargetServerUrl.TrimEnd('/'))/$targetPath"
                    }
                }
                if ($ServerUrl -and $Repository -and $Commit) {
                    $label = if ($UsePolicyLocations) { 'Policy definition' } else { 'Generated documentation' }
                    $message += "`n${label}: $($ServerUrl.TrimEnd('/'))/$Repository/blob/$Commit/$($location.path)#L$($location.line)"
                }
                $results.Add([ordered]@{
                        ruleId = $f.check
                        level = $sev.level
                        message = @{ text = $message }
                        locations = @(@{
                                physicalLocation = @{
                                    artifactLocation = @{ uri = $location.path; uriBaseId = '%SRCROOT%' }
                                    region = @{ startLine = $location.line }
                                }
                            })
                        # Stable target+check fingerprint, independent of the line number.
                        partialFingerprints = @{ 'gheComplianceTargetCheck/v1' = (Get-Fingerprint "$($target.id)|$($f.check)") }
                        properties = @{ target = $target.id; targetType = $target.type }
                    })
            }
        }

        $sarif = [ordered]@{
            '$schema' = 'https://json.schemastore.org/sarif-2.1.0.json'
            version = '2.1.0'
            runs = @(
                [ordered]@{
                    tool = @{
                        driver = [ordered]@{
                            name = 'github-enterprise-compliance'
                            informationUri = 'https://docs.github.com/en/code-security'
                            version = '1.0.0'
                            rules = @($rules.Values)
                        }
                    }
                    results = $results.ToArray()
                }
            )
        }

        $sarif | ConvertTo-Json -Depth 20 | Set-Content -Path $OutputFile -Encoding utf8NoBOM
        Write-Host "SARIF written to $OutputFile with $($results.Count) result(s) across $($rules.Count) rule(s)."
    }
}
