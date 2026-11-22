function Sync-GHComplianceIssue {
    <#
    .SYNOPSIS
        Creates, updates and closes compliance issues based on a findings file.

    .DESCRIPTION
        One issue per failing check and target, with content from the check's issue.md template.
        Issues are identified by hidden target and check markers. Existing grouped issues without
        a check marker are left untouched. Unevaluated checks never close their existing issues.
        By default issues are managed in the docs repository. With -IssuesInTargetRepositories,
        repository findings are managed in their respective repositories using the connected App;
        enterprise and organization findings remain in the docs repository.

    .EXAMPLE
        Test-GHCompliance | Sync-GHComplianceIssue -Repository contoso/github-docs -DryRun
    #>
    [CmdletBinding()]
    param(
        # Findings from Test-GHCompliance (pipeline), or a findings JSON file.
        [Parameter(ValueFromPipeline)] [object[]] $Findings,
        [string] $FindingsFile = './compliance-findings.json',
        [string] $Repository = $env:GITHUB_REPOSITORY,
        [string] $Token = $env:GITHUB_TOKEN,
        [string] $ApiBaseUrl = ($env:GITHUB_API_URL ?? 'https://api.github.com'),
        [string] $ServerUrl = ($env:GITHUB_SERVER_URL ?? 'https://github.com'),
        [string] $Branch = ($env:GITHUB_REF_NAME ?? 'main'),
        [string] $Label = 'compliance',
        [ValidateSet('enterprise', 'organization', 'user')]
        [string] $Scope = 'enterprise',
        [string] $Account,
        [string] $TemplatePath = (Join-Path $PSScriptRoot '../../../tests'),
        # Safety net against flooding the repo on the first run (e.g. 400 repos without CODEOWNERS).
        [int] $MaxNewIssues = 500,
        [switch] $IssuesInTargetRepositories,
        [switch] $DryRun
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
        #region API

        function Invoke-IssueApi {
            param(
                [Parameter(Mandatory)] [string] $Method,
                [Parameter(Mandatory)] [string] $Path,
                $Body,
                [switch] $Paginate
            )
            $headers = if ($IssuesInTargetRepositories -and $issueRepository -ne $Repository) {
                $targetHeaders = Get-RequestHeaders -Scope (Get-ScopeForPath "repos/$issueRepository")
                if (-not $targetHeaders) {
                    throw "No GitHub App installation token for $issueRepository."
                }
                $targetHeaders
            } else {
                @{
                    Authorization = "Bearer $Token"
                    Accept = 'application/vnd.github+json'
                    'X-GitHub-Api-Version' = '2022-11-28'
                }
            }
            $params = @{
                Method = $Method
                Uri = "$($ApiBaseUrl.TrimEnd('/'))/$($Path.TrimStart('/'))"
                Headers = $headers
            }
            if ($null -ne $Body) {
                $params.Body = $Body | ConvertTo-Json -Depth 10
                $params.ContentType = 'application/json'
            }
            for ($attempt = 0; ; $attempt++) {
                if ($Method -in 'Post', 'Patch', 'Put', 'Delete') {
                    Start-Sleep -Seconds 1
                }
                try {
                    if ($Paginate) {
                        $pages = Invoke-GHPaginatedRest -Uri $params.Uri -Headers $params.Headers -MaxPages 100
                        return @($pages | ForEach-Object { $_ })
                    }
                    return Invoke-RestMethod @params -ErrorAction Stop
                } catch {
                    $response = if ($_.Exception.PSObject.Properties['Response']) {
                        $_.Exception.Response
                    }
                    if (-not $response) {
                        throw
                    }
                    $status = [int]$response.StatusCode
                    $headers = $response.Headers
                    $retryAfter = if ($headers -and $headers.Contains('Retry-After')) {
                        @($headers.GetValues('Retry-After'))[0]
                    }
                    $remaining = if ($headers -and $headers.Contains('X-RateLimit-Remaining')) {
                        @($headers.GetValues('X-RateLimit-Remaining'))[0]
                    }
                    $details = if ($_.ErrorDetails) {
                        $_.ErrorDetails.Message
                    } else {
                        ''
                    }
                    $message = "$($_.Exception.Message) $details"
                    $rateLimited = $status -eq 429 -or ($status -eq 403 -and (
                            $retryAfter -or $remaining -eq '0' -or $message -match 'secondary rate limit|rate limit exceeded'
                        ))
                    if (-not $rateLimited -or $attempt -ge 3) {
                        throw
                    }
                    $delay = 60 * [math]::Pow(2, $attempt)
                    $seconds = 0
                    if ($retryAfter) {
                        if ([int]::TryParse([string]$retryAfter, [ref]$seconds) -and $seconds -ge 0) {
                            $delay = [math]::Max($delay, $seconds)
                        } else {
                            $retryDate = [DateTimeOffset]::MinValue
                            if (-not [DateTimeOffset]::TryParse([string]$retryAfter, [ref]$retryDate)) {
                                throw "GitHub returned an invalid Retry-After header; cannot safely retry. $message"
                            }
                            $delay = [math]::Max($delay, [math]::Ceiling(($retryDate - [DateTimeOffset]::UtcNow).TotalSeconds))
                        }
                    }
                    if ($remaining -eq '0') {
                        $reset = 0L
                        if (-not $headers.Contains('X-RateLimit-Reset') -or
                            -not [long]::TryParse([string]@($headers.GetValues('X-RateLimit-Reset'))[0], [ref]$reset)) {
                            throw "GitHub returned no valid rate-limit reset time; cannot safely retry. $message"
                        }
                        $delay = [math]::Max($delay, $reset - [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() + 1)
                    }
                    if ($delay -gt 900) {
                        throw "GitHub rate limit requires waiting $delay seconds; rerun issue synchronization after the limit resets. $message"
                    }
                    Write-Warning "GitHub rate limit reached for $Method $Path; retrying in $delay seconds (attempt $($attempt + 1) of 3)."
                    Start-Sleep -Seconds ([int]$delay)
                }
            }
        }

        function Invoke-Write {
            # Wraps every mutating call so -DryRun never changes anything.
            param([string] $Description, [scriptblock] $Action)
            if ($DryRun) {
                Write-Host "[dry-run] $Description"; return $null
            }
            Write-Host $Description
            return & $Action
        }

        #endregion

        #region Issue content

        function Get-IssueTitle {
            param($Target, $Failure)
            $kind = switch ($Target.type) {
                'enterprise' {
                    'Enterprise'
                } 'org' {
                    'Organization'
                } default {
                    'Repository'
                }
            }
            $name = if ($Target.type -eq 'enterprise') {
                $Target.org
            } else {
                $Target.id
            }
            return "[Compliance] $kind $name - $($Failure.title) ($($Failure.check))"
        }

        function Get-IssueLabels {
            param($Target, $Failure)
            return @($Label, "$Label`:$($Target.type)", "severity:$($Failure.severity)")
        }

        function Get-IssueBody {
            param($Target, $Failure, [string] $Template)

            $docsUrl = "$ServerUrl/$Repository/blob/$Branch/$($Target.docs)"
            $targetUrl = switch ($Target.type) {
                'enterprise' {
                    "$ServerUrl/enterprises/$($Target.org)"
                }
                'org' {
                    "$ServerUrl/$($Target.org)"
                }
                default {
                    "$ServerUrl/$($Target.id)"
                }
            }

            $values = @{
                target = [string]$Target.id; target_url = $targetUrl; docs_url = $docsUrl
                check = [string]$Failure.check; severity = [string]$Failure.severity
                finding = [string]$Failure.detail
            }
            $body = [regex]::Replace($Template.Replace("`r", ''), '\{\{([^{}]+)\}\}', {
                    param($match)
                    $name = $match.Groups[1].Value
                    if (-not $values.ContainsKey($name)) {
                        throw "Unknown issue template placeholder: $name"
                    }
                    return $values[$name]
                })
            return "<!-- compliance-target: $($Target.id) -->`n<!-- compliance-check: $($Failure.check) -->`n$($body.TrimEnd())"
        }

        #endregion

        #region Main

        function Invoke-Sync {
            if (-not $Repository) {
                throw 'No repository. Pass -Repository owner/name or run inside GitHub Actions.'
            }
            if (-not $Token -and -not $DryRun) {
                throw 'No token. Pass -Token or set GITHUB_TOKEN.'
            }
            if ($Scope -ne 'enterprise' -and [string]::IsNullOrWhiteSpace($Account)) {
                throw 'Account is required when synchronizing a single organization or user.'
            }
            if ($IssuesInTargetRepositories) {
                Assert-GHConnection
                if ($script:AuthMode -ne 'App') {
                    throw 'Target repository issue synchronization requires a GitHub App connection.'
                }
                if ($ApiBaseUrl.TrimEnd('/') -ne $script:ApiBaseUrl.TrimEnd('/')) {
                    throw 'Issue API URL must match the connected GitHub App API URL.'
                }
            }

            $findings = if ($Findings) {
                @($Findings)
            } else {
                @(Get-Content $FindingsFile -Raw | ConvertFrom-Json -Depth 20)
            }
            $byId = @{}
            foreach ($t in $findings) {
                $byId[$t.id] = $t
            }
            if ($Scope -ne 'enterprise') {
                $expectedType = if ($Scope -eq 'user') { 'account' } else { 'org' }
                if (-not $byId.ContainsKey($Account) -or $byId[$Account].type -ne $expectedType) {
                    throw "Findings do not contain the expected $expectedType inventory for '$Account'."
                }
            }
            $failing = @($findings | Where-Object { @($_.failures).Count -gt 0 })
            $issueRepositories = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
            [void]$issueRepositories.Add($Repository)
            if ($IssuesInTargetRepositories) {
                foreach ($target in @($findings | Where-Object { $_.type -eq 'repo' })) {
                    if ($target.id -notmatch '^[a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+$' -or
                        $target.id -match '(^|/)\.{1,2}(/|$)') {
                        throw "Invalid target repository: $($target.id)"
                    }
                    [void]$issueRepositories.Add([string]$target.id)
                }
            }

            # Validate every required template before making any changes to GitHub.
            $bodies = @{}
            foreach ($target in $failing) {
                foreach ($failure in $target.failures) {
                    if ($failure.check -notmatch '^[a-z0-9]+(?:[.-][a-z0-9]+)*$') {
                        throw "Invalid check ID: $($failure.check)"
                    }
                    $path = Join-Path (Join-Path $TemplatePath $failure.check) 'issue.md'
                    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
                        throw "Issue template not found: $path"
                    }
                    $key = "$($target.id)|$($failure.check)"
                    if ($bodies.ContainsKey($key)) {
                        throw "Duplicate finding for $key"
                    }
                    $bodies[$key] = Get-IssueBody $target $failure (Get-Content -LiteralPath $path -Raw -ErrorAction Stop)
                }
            }

            $stats = [ordered]@{ created = 0; updated = 0; unchanged = 0; closed = 0; kept = 0; skipped = 0 }

            foreach ($issueRepository in @($issueRepositories | Sort-Object)) {
                $repositoryFailures = @($failing | Where-Object {
                    if (-not $IssuesInTargetRepositories) { $true }
                    elseif ($_.type -eq 'repo') { $_.id -eq $issueRepository }
                    else { $issueRepository -eq $Repository }
                })

                # Only create missing labels, avoiding repeated validation errors on later runs.
                $labelDefs = @(
                    @{ name = $Label; color = '5319e7'; description = 'Managed by the compliance workflow' }
                    @{ name = "$Label`:org"; color = 'c5def5'; description = 'Organization-level compliance finding' }
                    @{ name = "$Label`:repo"; color = 'c5def5'; description = 'Repository-level compliance finding' }
                    @{ name = "$Label`:enterprise"; color = 'c5def5'; description = 'Enterprise-level compliance finding' }
                    @{ name = 'severity:high'; color = 'b60205'; description = '' }
                    @{ name = 'severity:medium'; color = 'fbca04'; description = '' }
                    @{ name = 'severity:low'; color = '0e8a16'; description = '' }
                )
                $existingLabels = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
                if ($Token) {
                    foreach ($existing in Invoke-IssueApi -Method Get -Path "repos/$issueRepository/labels?per_page=100" -Paginate) {
                        if ($existing.name) {
                            [void]$existingLabels.Add([string]$existing.name)
                        }
                    }
                }
                foreach ($def in $labelDefs) {
                    if ($IssuesInTargetRepositories -and $repositoryFailures.Count -eq 0) { break }
                    if ($existingLabels.Contains($def.name)) {
                        continue
                    }
                    try {
                        Invoke-Write "Ensure label $($def.name) in $issueRepository" { Invoke-IssueApi -Method Post -Path "repos/$issueRepository/labels" -Body $def } | Out-Null
                    } catch {
                        $response = if ($_.Exception.PSObject.Properties['Response']) {
                            $_.Exception.Response
                        }
                        $details = if ($_.ErrorDetails) {
                            $_.ErrorDetails.Message
                        } else {
                            ''
                        }
                        if (-not ($response -and [int]$response.StatusCode -eq 422 -and
                                "$($_.Exception.Message) $details" -match 'already_exists')) {
                            throw
                        }
                    }
                }

                # Grouped issues from the previous format deliberately remain untouched.
                $openIssues = @{}
                $legacyCount = 0
                if ($Token) {
                    foreach ($issue in Invoke-IssueApi -Method Get -Path "repos/$issueRepository/issues?state=open&labels=$Label&per_page=100" -Paginate) {
                        if ($issue.PSObject.Properties['pull_request']) {
                            continue
                        }
                        $body = [string]$issue.body
                        $targetMarker = [regex]::Match($body, '(?m)^<!-- compliance-target: (\S+) -->\r?$')
                        $checkMarker = [regex]::Match($body, '(?m)^<!-- compliance-check: ([a-z0-9]+(?:[.-][a-z0-9]+)*) -->\r?$')
                        if (-not $targetMarker.Success) {
                            continue
                        }
                        $issueTarget = $targetMarker.Groups[1].Value
                        if ($IssuesInTargetRepositories -and (
                            ($issueTarget.Contains('/') -and $issueTarget -ne $issueRepository) -or
                            (-not $issueTarget.Contains('/') -and $issueRepository -ne $Repository)
                        )) {
                            continue
                        }
                        if (-not $checkMarker.Success) {
                            $legacyCount++; continue
                        }
                        $key = "$($targetMarker.Groups[1].Value)|$($checkMarker.Groups[1].Value)"
                        if ($openIssues.ContainsKey($key)) {
                            throw "Multiple open compliance issues for $key"
                        }
                        $openIssues[$key] = $issue
                    }
                }
                if ($legacyCount -gt 0) {
                    Write-Warning "$legacyCount existing grouped compliance issue(s) were left untouched; review them manually."
                }

                # Create / update.
                foreach ($target in $repositoryFailures) {
                    foreach ($failure in $target.failures) {
                        $key = "$($target.id)|$($failure.check)"
                        $title = Get-IssueTitle $target $failure
                        $body = $bodies[$key]
                        $labels = Get-IssueLabels $target $failure

                        if ($openIssues.ContainsKey($key)) {
                            $issue = $openIssues[$key]
                            $currentLabels = @($issue.labels | ForEach-Object name | Sort-Object)
                            $sameBody = ([string]$issue.body).Replace("`r", '') -eq $body
                            $sameLabels = ($currentLabels -join ',') -eq (@($labels | Sort-Object) -join ',')
                            if ($sameBody -and $sameLabels -and $issue.title -eq $title) {
                                $stats.unchanged++; continue
                            }
                            Invoke-Write "Update $issueRepository#$($issue.number) $title" {
                                Invoke-IssueApi -Method Patch -Path "repos/$issueRepository/issues/$($issue.number)" -Body @{ title = $title; body = $body; labels = $labels }
                            } | Out-Null
                            $stats.updated++
                        } elseif ($stats.created -ge $MaxNewIssues) {
                            $stats.skipped++
                        } else {
                            Invoke-Write "Create $title in $issueRepository" {
                                Invoke-IssueApi -Method Post -Path "repos/$issueRepository/issues" -Body @{ title = $title; body = $body; labels = $labels }
                            } | Out-Null
                            $stats.created++
                        }
                    }
                }

                # Close only when this specific check can be evaluated or the target was removed.
                foreach ($key in @($openIssues.Keys | Sort-Object)) {
                    $issue = $openIssues[$key]
                    $id, $check = $key.Split('|', 2)
                    if ($Scope -ne 'enterprise' -and
                        ($id -ne $Account -and -not $id.StartsWith("$Account/", [StringComparison]::OrdinalIgnoreCase))) {
                        $stats.kept++; continue
                    }
                    if ($Scope -eq 'user' -and -not $id.Contains('/')) {
                        $stats.kept++; continue
                    }
                    $target = $byId[$id]
                    $reason = $null

                    if ($target) {
                        if (@($target.failures | Where-Object { $_.check -eq $check }).Count -gt 0) {
                            continue
                        }
                        $unknown = @(@($target.notEvaluated) | Where-Object { $_ -and $_.check -eq $check })
                        if ($unknown.Count -gt 0) {
                            $stats.kept++; continue
                        }
                        $reason = "This check no longer reports a failure. Closing automatically."
                    } else {
                        $org = $id.Split('/')[0]
                        $orgTarget = $byId[$org]
                        if ($id.Contains('/') -and $orgTarget -and -not $orgTarget.reposEvaluated) {
                            $stats.kept++; continue
                        }
                        $reason = if ($id.Contains('/') -and $orgTarget) {
                            'Repository no longer exists or has been archived. Closing automatically.'
                        } else {
                            'Target no longer exists in the enterprise. Closing automatically.'
                        }
                    }

                    Invoke-Write "Close $issueRepository#$($issue.number) ($id)" {
                        Invoke-IssueApi -Method Post -Path "repos/$issueRepository/issues/$($issue.number)/comments" -Body @{ body = $reason } | Out-Null
                        Invoke-IssueApi -Method Patch -Path "repos/$issueRepository/issues/$($issue.number)" -Body @{ state = 'closed'; state_reason = 'completed' } | Out-Null
                    } | Out-Null
                    $stats.closed++
                }
            }

            $summary = "Compliance: $($failing.Count) non-compliant target(s). " + (($stats.GetEnumerator() | ForEach-Object { "$($_.Key): $($_.Value)" }) -join ', ')
            Write-Host $summary
            if ($stats.skipped -gt 0) {
                Write-Warning "$($stats.skipped) new issue(s) not created because -MaxNewIssues ($MaxNewIssues) was reached. They will be created in later runs."
            }
            if ($env:GITHUB_STEP_SUMMARY) {
                @(
                    '### Compliance'
                    ''
                    '| Result | Count |'
                    '| --- | --- |'
                    "| Non-compliant targets | $($failing.Count) |"
                    ($stats.GetEnumerator() | ForEach-Object { "| Issues $($_.Key) | $($_.Value) |" })
                ) -join "`n" | Add-Content -Path $env:GITHUB_STEP_SUMMARY
            }
        }

        Invoke-Sync

        #endregion
    }
}
