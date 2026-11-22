BeforeAll {
    $root = Join-Path $PSScriptRoot '../..'
    Import-Module (Join-Path $root 'src/GitHubGovernance/GitHubGovernance.psd1') -Force

    function New-Failure([string] $Check, [string] $Detail = 'Observed failure') {
        return [pscustomobject]@{ check = $Check; title = $Check; severity = 'high'; detail = $Detail }
    }

    function New-Target([object[]] $Failures = @(), [object[]] $NotEvaluated = @()) {
        return [pscustomobject]@{
            id = 'example'; type = 'org'; org = 'example'; docs = 'docs/example.md'
            reposEvaluated = $true; failures = $Failures; notEvaluated = $NotEvaluated
        }
    }

    function New-OpenIssue([int] $Number, [string] $Check, [string] $Target = 'example') {
        $body = "<!-- compliance-target: $Target -->"
        if ($Check) {
            $body += "`n<!-- compliance-check: $Check -->"
        }
        return [pscustomobject]@{ number = $Number; body = $body; title = 'Old'; labels = @() }
    }
}

Describe 'Per-check issue synchronization' {
    BeforeEach {
        $global:IssueSyncCalls = [System.Collections.Generic.List[object]]::new()
        $global:IssueSyncOpen = @()
        $global:IssueSyncOpenByRepo = @{}
        $global:IssueSyncLabels = @()
        $global:IssueSyncSleeps = [System.Collections.Generic.List[int]]::new()
        Mock Start-Sleep -ModuleName GitHubGovernance {
            param($Seconds)
            $global:IssueSyncSleeps.Add($Seconds)
        }
        Mock Invoke-RestMethod -ModuleName GitHubGovernance {
            param($Uri, $Method, $Body, $Headers)
            $global:IssueSyncCalls.Add([pscustomobject]@{
                    uri = $Uri; method = $Method; authorization = $Headers.Authorization
                    body = $(if ($Body) {
                            $Body | ConvertFrom-Json
                        } else {
                            $null
                        })
                })
            if ($Method -eq 'Get') {
                if ($Uri -match '/labels\?') {
                    return $global:IssueSyncLabels
                }
                foreach ($repository in $global:IssueSyncOpenByRepo.Keys) {
                    if ($Uri -like "*/repos/$repository/issues?*") {
                        return $global:IssueSyncOpenByRepo[$repository]
                    }
                }
                return $global:IssueSyncOpen
            }
            return [pscustomobject]@{}
        }
    }

    AfterAll {
        Remove-Variable IssueSyncCalls, IssueSyncOpen, IssueSyncOpenByRepo, IssueSyncLabels, IssueSyncSleeps, IssueSyncAttempts,
        IssueSyncRateHeader, IssueSyncRateValue -Scope Global -ErrorAction SilentlyContinue
    }

    It 'creates a separate rendered issue for each failed check' {
        $target = New-Target @((New-Failure 'org.2fa-required' '2FA disabled'), (New-Failure 'org.webhooks-tls' 'TLS disabled'))
        Sync-GHComplianceIssue -Findings $target -Repository 'owner/docs' -Token 'fake' -ServerUrl 'https://github.example' -Branch 'main' 6>$null
        $created = @($global:IssueSyncCalls | Where-Object { $_.method -eq 'Post' -and $_.uri -match '/issues$' })
        $created.Count | Should -Be 2
        $created[0].body.title | Should -Match 'org\.2fa-required'
        $created[0].body.body | Should -Match '<!-- compliance-check: org\.2fa-required -->'
        $created[0].body.body | Should -Match '2FA disabled'
        $created[0].body.body | Should -Match 'credential theft'
        $created[0].body.body | Should -Match 'https://github.example/owner/docs/blob/main/docs/example.md'
        $created[0].body.body | Should -Not -Match '\{\{'
        $created[1].body.body | Should -Match 'TLS disabled'
        $created[1].body.body | Should -Match 'interception or tampering'
    }

    It 'includes CIS identification and manual review in partial-control issues' {
        $target = New-Target @((New-Failure 'org.apps-selected-repositories' 'One app has broad access'))
        Sync-GHComplianceIssue -Findings $target -Repository 'owner/docs' -Token 'fake' 6>$null
        $issue = @($global:IssueSyncCalls | Where-Object { $_.method -eq 'Post' -and $_.uri -match '/issues$' })[0].body.body
        $issue | Should -Match '1\.4\.3'
        $issue | Should -Match 'partial assessment'
        $issue | Should -Match 'Review each app permission'
        $issue | Should -Match 'One app has broad access'
    }

    It 'updates the matching check and closes only a different resolved check' {
        $global:IssueSyncOpen = @((New-OpenIssue 1 'org.2fa-required'), (New-OpenIssue 2 'org.webhooks-tls'))
        $target = New-Target @((New-Failure 'org.2fa-required'))
        Sync-GHComplianceIssue -Findings $target -Repository 'owner/docs' -Token 'fake' 6>$null
        $updates = @($global:IssueSyncCalls | Where-Object { $_.method -eq 'Patch' })
        @($updates | Where-Object { $_.uri -match '/issues/1$' -and $_.body.body -match 'org.2fa-required' }).Count | Should -Be 1
        @($updates | Where-Object { $_.uri -match '/issues/2$' -and $_.body.state -eq 'closed' }).Count | Should -Be 1
    }

    It 'routes repository issues to their targets and keeps centralized repository issues untouched' {
        & (Get-Module GitHubGovernance) {
            $script:Connection = [pscustomobject]@{ Scope = 'enterprise' }
            $script:AuthMode = 'App'
            $script:ApiBaseUrl = 'https://api.github.com'
        }
        Mock Get-RequestHeaders -ModuleName GitHubGovernance {
            param($Scope)
            return @{ Authorization = "Bearer app-$Scope"; Accept = 'application/vnd.github+json' }
        }
        $org = New-Target @((New-Failure 'org.2fa-required'))
        $enterprise = [pscustomobject]@{
            id = 'enterprise:example'; type = 'enterprise'; org = 'example'; docs = 'docs/enterprise.md'
            failures = @((New-Failure 'enterprise.max-owners')); notEvaluated = @()
        }
        $repo = [pscustomobject]@{
            id = 'example/one'; type = 'repo'; org = 'example'; docs = 'docs/example/one.md'
            failures = @((New-Failure 'repo.stale'), (New-Failure 'repo.readme-present')); notEvaluated = @()
        }
        $resolved = [pscustomobject]@{
            id = 'example/two'; type = 'repo'; org = 'example'; docs = 'docs/example/two.md'
            failures = @(); notEvaluated = @([pscustomobject]@{ check = 'repo.secret-scanning' })
        }
        $global:IssueSyncOpenByRepo['owner/docs'] = @((New-OpenIssue 1 'repo.stale' 'example/one'))
        $global:IssueSyncOpenByRepo['example/one'] = @((New-OpenIssue 4 'repo.readme-present' 'example/one'))
        $global:IssueSyncOpenByRepo['example/two'] = @(
            (New-OpenIssue 2 'repo.stale' 'example/two'),
            (New-OpenIssue 3 'repo.secret-scanning' 'example/two')
        )
        try {
            Sync-GHComplianceIssue -Findings @($enterprise, $org, $repo, $resolved) -Repository 'owner/docs' -Token 'docs-token' -IssuesInTargetRepositories 6>$null
            $created = @($global:IssueSyncCalls | Where-Object { $_.method -eq 'Post' -and $_.uri -match '/issues$' })
            @($created | Where-Object { $_.uri -match '/repos/owner/docs/issues$' -and $_.authorization -eq 'Bearer docs-token' }).Count | Should -Be 2
            $targetIssue = @($created | Where-Object { $_.uri -match '/repos/example/one/issues$' })
            $targetIssue.Count | Should -Be 1
            $targetIssue[0].authorization | Should -Be 'Bearer app-org:example'
            $targetIssue[0].body.body | Should -Match 'https://github.com/owner/docs/blob/main/docs/example/one.md'
            @($global:IssueSyncCalls | Where-Object { $_.method -eq 'Patch' -and $_.uri -match '/repos/example/one/issues/4$' -and $_.authorization -eq 'Bearer app-org:example' }).Count | Should -Be 1
            $closed = @($global:IssueSyncCalls | Where-Object { $_.method -eq 'Patch' -and $_.body.state -eq 'closed' })
            $closed.Count | Should -Be 1
            $closed[0].uri | Should -Match '/repos/example/two/issues/2$'
            @($global:IssueSyncCalls | Where-Object { $_.uri -match '/repos/owner/docs/issues/1' }).Count | Should -Be 0
        } finally {
            Disconnect-GHGovernance
        }
    }

    It 'requires matching App authentication for target repository issues' {
        & (Get-Module GitHubGovernance) {
            $script:Connection = [pscustomobject]@{ Scope = 'enterprise' }
            $script:AuthMode = 'App'
            $script:ApiBaseUrl = 'https://api.github.com'
        }
        try {
            { Sync-GHComplianceIssue -Findings (New-Target) -Repository 'owner/docs' -Token 'fake' -IssuesInTargetRepositories -ApiBaseUrl 'https://other.example' } |
                Should -Throw '*must match*'
            $global:IssueSyncCalls.Count | Should -Be 0
        } finally {
            Disconnect-GHGovernance
        }
    }

    It 'fails explicitly when a target installation token is unavailable' {
        & (Get-Module GitHubGovernance) {
            $script:Connection = [pscustomobject]@{ Scope = 'enterprise' }
            $script:AuthMode = 'App'
            $script:ApiBaseUrl = 'https://api.github.com'
        }
        Mock Get-RequestHeaders -ModuleName GitHubGovernance { return $null }
        $repo = [pscustomobject]@{
            id = 'example/repo'; type = 'repo'; org = 'example'; docs = 'docs/repo.md'
            failures = @(); notEvaluated = @()
        }
        try {
            { Sync-GHComplianceIssue -Findings $repo -Repository 'owner/docs' -Token 'fake' -IssuesInTargetRepositories 6>$null } |
                Should -Throw '*No GitHub App installation token for example/repo*'
        } finally {
            Disconnect-GHGovernance
        }
    }

    It 'applies the new issue limit across all destinations' {
        & (Get-Module GitHubGovernance) {
            $script:Connection = [pscustomobject]@{ Scope = 'enterprise' }
            $script:AuthMode = 'App'
            $script:ApiBaseUrl = 'https://api.github.com'
        }
        Mock Get-RequestHeaders -ModuleName GitHubGovernance {
            return @{ Authorization = 'Bearer app-token' }
        }
        $repo = [pscustomobject]@{
            id = 'example/repo'; type = 'repo'; org = 'example'; docs = 'docs/repo.md'
            failures = @((New-Failure 'repo.stale')); notEvaluated = @()
        }
        try {
            Sync-GHComplianceIssue -Findings @((New-Target @((New-Failure 'org.2fa-required'))), $repo) `
                -Repository 'owner/docs' -Token 'fake' -IssuesInTargetRepositories -MaxNewIssues 1 -WarningAction SilentlyContinue 6>$null
            @($global:IssueSyncCalls | Where-Object { $_.method -eq 'Post' -and $_.uri -match '/issues$' }).Count | Should -Be 1
        } finally {
            Disconnect-GHGovernance
        }
    }

    It 'does not update an unchanged issue on the next run' {
        $target = New-Target @((New-Failure 'org.2fa-required'))
        Sync-GHComplianceIssue -Findings $target -Repository 'owner/docs' -Token 'fake' 6>$null
        $created = @($global:IssueSyncCalls | Where-Object { $_.method -eq 'Post' -and $_.uri -match '/issues$' })[0].body
        $global:IssueSyncOpen = @([pscustomobject]@{
                number = 1; title = $created.title; body = $created.body
                labels = @($created.labels | ForEach-Object { [pscustomobject]@{ name = $_ } })
            })
        $global:IssueSyncCalls.Clear()
        Sync-GHComplianceIssue -Findings $target -Repository 'owner/docs' -Token 'fake' 6>$null
        @($global:IssueSyncCalls | Where-Object { $_.method -eq 'Patch' -or ($_.method -eq 'Post' -and $_.uri -match '/issues$') }).Count | Should -Be 0
    }

    It 'keeps unevaluated checks and old grouped issues untouched' {
        $global:IssueSyncOpen = @((New-OpenIssue 1 'org.2fa-required'), (New-OpenIssue 2 ''), (New-OpenIssue 3 'repo.stale' 'example/repo'))
        $target = New-Target @((New-Failure 'org.webhooks-tls')) @([pscustomobject]@{ check = 'org.2fa-required'; reason = 'Unavailable' })
        $target.reposEvaluated = $false
        Sync-GHComplianceIssue -Findings $target -Repository 'owner/docs' -Token 'fake' -WarningAction SilentlyContinue 6>$null
        @($global:IssueSyncCalls | Where-Object { $_.method -eq 'Patch' }).Count | Should -Be 0
    }

    It 'closes only removed repositories in the configured personal account' {
        $global:IssueSyncOpen = @(
            (New-OpenIssue 1 'repo.stale' 'example/deleted'),
            (New-OpenIssue 2 'repo.stale' 'another/repo'),
            (New-OpenIssue 3 'org.2fa-required' 'example'),
            (New-OpenIssue 4 'enterprise.max-owners' 'enterprise:example')
        )
        $account = New-Target
        $account.type = 'account'
        Sync-GHComplianceIssue -Findings $account -Repository 'owner/docs' -Token 'fake' -Scope user -Account example 6>$null
        $closed = @($global:IssueSyncCalls | Where-Object { $_.method -eq 'Patch' -and $_.body.state -eq 'closed' })
        $closed.Count | Should -Be 1
        $closed[0].uri | Should -Match '/issues/1$'
    }

    It 'refuses a scoped sync when the expected inventory is absent' {
        $target = New-Target
        { Sync-GHComplianceIssue -Findings $target -Repository 'owner/docs' -Token 'fake' -Scope user -Account example 6>$null } |
            Should -Throw '*expected account inventory*'
        $global:IssueSyncCalls.Count | Should -Be 0
    }

    It 'fails before writes when a required template is missing' {
        $target = New-Target @((New-Failure 'org.unknown'))
        { Sync-GHComplianceIssue -Findings $target -Repository 'owner/docs' -Token 'fake' 6>$null } | Should -Throw '*Issue template not found*'
        $global:IssueSyncCalls.Count | Should -Be 0
    }

    It 'rejects invalid check IDs before reading a template' {
        $target = New-Target @((New-Failure '..'))
        { Sync-GHComplianceIssue -Findings $target -Repository 'owner/docs' -Token 'fake' 6>$null } | Should -Throw '*Invalid check ID*'
        $global:IssueSyncCalls.Count | Should -Be 0
    }

    It 'rejects unknown placeholders before making API calls' {
        New-Item -ItemType Directory -Path "$TestDrive/org.2fa-required" | Out-Null
        Set-Content -Path "$TestDrive/org.2fa-required/issue.md" -Value 'Invalid {{severity_level}}'
        $target = New-Target @((New-Failure 'org.2fa-required'))
        { Sync-GHComplianceIssue -Findings $target -Repository 'owner/docs' -Token 'fake' -TemplatePath $TestDrive 6>$null } | Should -Throw '*Unknown issue template placeholder*'
        $global:IssueSyncCalls.Count | Should -Be 0
    }

    It 'renders a template for every configured check' {
        $policy = Get-Content (Join-Path $root 'compliance/policy.json') -Raw | ConvertFrom-Json
        $failures = @($policy.checks.PSObject.Properties | ForEach-Object { New-Failure $_.Name })
        $target = New-Target $failures
        Sync-GHComplianceIssue -Findings $target -Repository 'owner/docs' -Token 'fake' 6>$null
        $created = @($global:IssueSyncCalls | Where-Object { $_.method -eq 'Post' -and $_.uri -match '/issues$' })
        $created.Count | Should -Be $failures.Count
        foreach ($issue in $created) {
            $issue.body.body | Should -Not -Match '\{\{'
            $issue.body.body | Should -Match 'Observed failure'
        }
    }

    It 'preserves placeholders appearing in observed findings' {
        $target = New-Target @((New-Failure 'org.2fa-required' 'Observed {{target}}'))
        Sync-GHComplianceIssue -Findings $target -Repository 'owner/docs' -Token 'fake' 6>$null
        $created = @($global:IssueSyncCalls | Where-Object { $_.method -eq 'Post' -and $_.uri -match '/issues$' })
        $created[0].body.body | Should -Match 'Observed \{\{target\}\}'
    }

    It 'does not recreate existing labels and paces mutating requests' {
        $global:IssueSyncLabels = @('compliance', 'compliance:org', 'compliance:repo', 'compliance:enterprise',
            'severity:high', 'severity:medium', 'severity:low' | ForEach-Object { [pscustomobject]@{ name = $_ } })
        $target = New-Target @((New-Failure 'org.2fa-required'), (New-Failure 'org.webhooks-tls'))
        Sync-GHComplianceIssue -Findings $target -Repository 'owner/docs' -Token 'fake' 6>$null
        @($global:IssueSyncCalls | Where-Object { $_.method -eq 'Post' -and $_.uri -match '/labels$' }).Count | Should -Be 0
        @($global:IssueSyncSleeps | Where-Object { $_ -eq 1 }).Count | Should -Be 2
    }

    It 'backs off and retries an explicit secondary rate limit' {
        $global:IssueSyncAttempts = 0
        Mock Invoke-RestMethod -ModuleName GitHubGovernance -ParameterFilter {
            $Method -eq 'Post' -and $Uri -match '/issues$'
        } {
            $global:IssueSyncAttempts++
            if ($global:IssueSyncAttempts -eq 1) {
                $response = [System.Net.Http.HttpResponseMessage]::new([System.Net.HttpStatusCode]::Forbidden)
                $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                    [Microsoft.PowerShell.Commands.HttpResponseException]::new('Forbidden', $response),
                    'RateLimit', [System.Management.Automation.ErrorCategory]::InvalidOperation, $null)
                $errorRecord.ErrorDetails = [System.Management.Automation.ErrorDetails]::new('You have exceeded a secondary rate limit')
                throw $errorRecord
            }
            return [pscustomobject]@{}
        }
        $target = New-Target @((New-Failure 'org.2fa-required'))
        Sync-GHComplianceIssue -Findings $target -Repository 'owner/docs' -Token 'fake' -WarningAction SilentlyContinue 6>$null
        $global:IssueSyncAttempts | Should -Be 2
        $global:IssueSyncSleeps | Should -Contain 60
    }

    It 'honors Retry-After and stops after bounded retries' {
        $global:IssueSyncAttempts = 0
        Mock Invoke-RestMethod -ModuleName GitHubGovernance -ParameterFilter {
            $Method -eq 'Post' -and $Uri -match '/issues$'
        } {
            $global:IssueSyncAttempts++
            $response = [System.Net.Http.HttpResponseMessage]::new([System.Net.HttpStatusCode]::TooManyRequests)
            [void]$response.Headers.TryAddWithoutValidation('Retry-After', '180')
            throw [Microsoft.PowerShell.Commands.HttpResponseException]::new('Rate limited', $response)
        }
        $target = New-Target @((New-Failure 'org.2fa-required'))
        { Sync-GHComplianceIssue -Findings $target -Repository 'owner/docs' -Token 'fake' -WarningAction SilentlyContinue 6>$null } |
            Should -Throw '*Rate limited*'
        $global:IssueSyncAttempts | Should -Be 4
        @($global:IssueSyncSleeps | Where-Object { $_ -ge 60 }) | Should -Be @(180, 180, 240)
    }

    It 'waits for the primary rate limit reset before retrying' {
        $global:IssueSyncAttempts = 0
        Mock Invoke-RestMethod -ModuleName GitHubGovernance -ParameterFilter {
            $Method -eq 'Post' -and $Uri -match '/issues$'
        } {
            $global:IssueSyncAttempts++
            if ($global:IssueSyncAttempts -eq 1) {
                $response = [System.Net.Http.HttpResponseMessage]::new([System.Net.HttpStatusCode]::Forbidden)
                [void]$response.Headers.TryAddWithoutValidation('X-RateLimit-Remaining', '0')
                [void]$response.Headers.TryAddWithoutValidation('X-RateLimit-Reset', [string]([DateTimeOffset]::UtcNow.ToUnixTimeSeconds() + 180))
                throw [Microsoft.PowerShell.Commands.HttpResponseException]::new('Rate limited', $response)
            }
            return [pscustomobject]@{}
        }
        $target = New-Target @((New-Failure 'org.2fa-required'))
        Sync-GHComplianceIssue -Findings $target -Repository 'owner/docs' -Token 'fake' -WarningAction SilentlyContinue 6>$null
        $global:IssueSyncAttempts | Should -Be 2
        @($global:IssueSyncSleeps | Where-Object { $_ -ge 179 -and $_ -le 182 }).Count | Should -Be 1
    }

    It 'fails instead of retrying early when the requested delay is too long' {
        $global:IssueSyncAttempts = 0
        Mock Invoke-RestMethod -ModuleName GitHubGovernance -ParameterFilter {
            $Method -eq 'Post' -and $Uri -match '/issues$'
        } {
            $global:IssueSyncAttempts++
            $response = [System.Net.Http.HttpResponseMessage]::new([System.Net.HttpStatusCode]::TooManyRequests)
            [void]$response.Headers.TryAddWithoutValidation('Retry-After', '901')
            throw [Microsoft.PowerShell.Commands.HttpResponseException]::new('Rate limited', $response)
        }
        $target = New-Target @((New-Failure 'org.2fa-required'))
        { Sync-GHComplianceIssue -Findings $target -Repository 'owner/docs' -Token 'fake' 6>$null } |
            Should -Throw '*requires waiting 901 seconds*'
        $global:IssueSyncAttempts | Should -Be 1
        @($global:IssueSyncSleeps | Where-Object { $_ -ge 60 }).Count | Should -Be 0
    }

    It 'does not guess when a rate-limit delay is invalid or missing' -TestCases @(
        @{ header = 'Retry-After'; value = 'invalid'; expected = '*invalid Retry-After*' }
        @{ header = 'X-RateLimit-Remaining'; value = '0'; expected = '*no valid rate-limit reset time*' }
    ) {
        $global:IssueSyncAttempts = 0
        $global:IssueSyncRateHeader = $header
        $global:IssueSyncRateValue = $value
        Mock Invoke-RestMethod -ModuleName GitHubGovernance -ParameterFilter {
            $Method -eq 'Post' -and $Uri -match '/issues$'
        } {
            $global:IssueSyncAttempts++
            $response = [System.Net.Http.HttpResponseMessage]::new([System.Net.HttpStatusCode]::TooManyRequests)
            [void]$response.Headers.TryAddWithoutValidation($global:IssueSyncRateHeader, $global:IssueSyncRateValue)
            throw [Microsoft.PowerShell.Commands.HttpResponseException]::new('Rate limited', $response)
        }
        $target = New-Target @((New-Failure 'org.2fa-required'))
        { Sync-GHComplianceIssue -Findings $target -Repository 'owner/docs' -Token 'fake' 6>$null } |
            Should -Throw $expected
        $global:IssueSyncAttempts | Should -Be 1
        @($global:IssueSyncSleeps | Where-Object { $_ -ge 60 }).Count | Should -Be 0
    }

    It 'does not retry or suppress unrelated forbidden errors' {
        $global:IssueSyncAttempts = 0
        Mock Invoke-RestMethod -ModuleName GitHubGovernance -ParameterFilter {
            $Method -eq 'Post' -and $Uri -match '/labels$'
        } {
            $global:IssueSyncAttempts++
            $response = [System.Net.Http.HttpResponseMessage]::new([System.Net.HttpStatusCode]::Forbidden)
            throw [Microsoft.PowerShell.Commands.HttpResponseException]::new('Forbidden', $response)
        }
        $target = New-Target @((New-Failure 'org.2fa-required'))
        { Sync-GHComplianceIssue -Findings $target -Repository 'owner/docs' -Token 'fake' 6>$null } |
            Should -Throw '*Forbidden*'
        $global:IssueSyncAttempts | Should -Be 1
        @($global:IssueSyncSleeps | Where-Object { $_ -ge 60 }).Count | Should -Be 0
    }
}
