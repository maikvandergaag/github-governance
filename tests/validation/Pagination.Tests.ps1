BeforeAll {
    $root = Join-Path $PSScriptRoot '../..'
    Import-Module (Join-Path $root 'src/GitHubGovernance/GitHubGovernance.psd1') -Force
    $script:module = Get-Module GitHubGovernance

    $socket = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
    $socket.Start()
    $script:port = $socket.LocalEndpoint.Port
    $socket.Stop()
    $script:base = "http://127.0.0.1:$script:port"
    $script:server = Start-Job -ArgumentList $script:port -ScriptBlock {
        param($port)
        $base = "http://127.0.0.1:$port"
        $listener = [System.Net.HttpListener]::new()
        $listener.Prefixes.Add("$base/")
        $listener.Start()
        Write-Output 'ready'
        try {
            while ($true) {
                $pending = $listener.BeginGetContext($null, $null)
                while (-not $pending.AsyncWaitHandle.WaitOne(100)) {
                    Start-Sleep -Milliseconds 1
                }
                $ctx = $listener.EndGetContext($pending)
                $path = $ctx.Request.Url.AbsolutePath
                $page = $ctx.Request.QueryString['page']
                $authenticated = $ctx.Request.Headers['Authorization'] -eq 'Bearer fixture'
                Write-Output ([pscustomobject]@{ method = $ctx.Request.HttpMethod; path = $path; page = $page; authenticated = $authenticated })
                $body = '{}'
                if (-not $authenticated) {
                    $ctx.Response.StatusCode = 401
                    $body = '{"message":"Unauthorized"}'
                } elseif ($path -eq '/foreign') {
                    $ctx.Response.AddHeader('Link', '<http://localhost:1/other>; rel="next"')
                    $body = '[]'
                } elseif ($path -eq '/cycle') {
                    $ctx.Response.AddHeader('Link', "<$base/cycle>; rel=`"next`"")
                    $body = '[]'
                } elseif ($path -eq '/unavailable' -and $page -eq '2') {
                    $ctx.Response.StatusCode = 403
                    $body = '{"message":"Forbidden"}'
                } elseif ($path -eq '/orgs/example/wrapped') {
                    if ($page -ne '2') {
                        $ctx.Response.AddHeader('Link', "<$base${path}?page=2>; rel=`"next`"")
                        $body = '{"items":[{"id":1}]}'
                    } else {
                        $body = '{"items":[{"id":2}]}'
                    }
                } elseif ($path -in '/items', '/unavailable', '/orgs/example/repos') {
                    if ($page -ne '2') {
                        $ctx.Response.AddHeader('Link', "<$base${path}?page=2>; rel=`"next`"")
                        $body = '[{"id":1}]'
                    } else {
                        $body = '[{"id":2}]'
                    }
                } elseif ($path -eq '/repos/owner/docs/labels' -and $ctx.Request.HttpMethod -eq 'GET') {
                    $body = '[]'
                } elseif ($path -eq '/repos/owner/docs/issues' -and $ctx.Request.HttpMethod -eq 'GET') {
                    if ($page -ne '2') {
                        $ctx.Response.AddHeader('Link', "<$base${path}?page=2>; rel=`"next`"")
                        $body = '[]'
                    } else {
                        $body = '[{"number":41,"title":"Old","body":"<!-- compliance-target: example -->\n<!-- compliance-check: org.2fa-required -->","labels":[]}]'
                    }
                }
                $bytes = [Text.Encoding]::UTF8.GetBytes($body)
                $ctx.Response.ContentType = 'application/json'
                $ctx.Response.ContentLength64 = $bytes.Length
                $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
                $ctx.Response.Close()
            }
        } finally {
            $listener.Close()
        }
    }
    $ready = $false
    for ($i = 0; $i -lt 100; $i++) {
        if (@(Receive-Job $script:server -Keep | Where-Object { $_ -is [string] -and $_ -eq 'ready' }).Count) {
            $ready = $true
            break
        }
        Start-Sleep -Milliseconds 50
    }
    if (-not $ready) {
        throw 'Pagination test server did not start.'
    }
}

AfterAll {
    if ($script:server) {
        Stop-Job $script:server
        Remove-Job $script:server -Force
    }
}

Describe 'Authenticated GitHub pagination' {
    It 'uses authorization for every page and returns each result' {
        $pages = & $script:module {
            param($base)
            Invoke-GHPaginatedRest -Uri "$base/items" -Headers @{ Authorization = 'Bearer fixture' }
        } $script:base
        $pages.Count | Should -Be 2
        $pages[0][0].id | Should -Be 1
        $pages[1][0].id | Should -Be 2
    }

    It 'flattens inventory pages' {
        Connect-GHGovernance -Enterprise example -Token 'fixture' -ApiBaseUrl $script:base | Out-Null
        try {
            $inventory = & $script:module { Invoke-GitHubRest -Path 'orgs/example/repos' -Paginate }
            $inventory.Ok | Should -BeTrue
            @($inventory.Data.id) | Should -Be @(1, 2)
            $wrapped = & $script:module { Invoke-GitHubRest -Path 'orgs/example/wrapped' -Paginate -ItemProperty 'items' }
            $wrapped.Ok | Should -BeTrue
            @($wrapped.Data.id) | Should -Be @(1, 2)
        } finally {
            Disconnect-GHGovernance
        }
    }

    It 'finds an existing issue on a later page instead of creating a duplicate' {
        Mock Start-Sleep -ModuleName GitHubGovernance {}
        $target = [pscustomobject]@{
            id = 'example'; type = 'org'; org = 'example'; docs = 'docs/example.md'; reposEvaluated = $true
            failures = @([pscustomobject]@{ check = 'org.2fa-required'; title = '2FA'; severity = 'high'; detail = 'disabled' })
            notEvaluated = @()
        }
        Sync-GHComplianceIssue -Findings $target -Repository 'owner/docs' -Token 'fixture' -ApiBaseUrl $script:base 6>$null
        $calls = @(Receive-Job $script:server -Keep | Where-Object { $_ -isnot [string] })
        @($calls | Where-Object { $_.path -eq '/repos/owner/docs/issues' -and $_.page -eq '2' -and $_.authenticated }).Count | Should -Be 1
        @($calls | Where-Object { $_.path -eq '/repos/owner/docs/issues/41' -and $_.method -eq 'PATCH' }).Count | Should -Be 1
        @($calls | Where-Object { $_.path -eq '/repos/owner/docs/issues' -and $_.method -eq 'POST' }).Count | Should -Be 0
    }

    It 'rejects links to a different origin and pagination cycles' {
        { & $script:module { param($base) Invoke-GHPaginatedRest -Uri "$base/foreign" -Headers @{ Authorization = 'Bearer fixture' } } $script:base } |
            Should -Throw '*different pagination origin*'
        { & $script:module { param($base) Invoke-GHPaginatedRest -Uri "$base/cycle" -Headers @{ Authorization = 'Bearer fixture' } } $script:base } |
            Should -Throw '*cycle detected*'
        { & $script:module { param($base) Invoke-GHPaginatedRest -Uri "$base/items" -Headers @{ Authorization = 'Bearer fixture' } -MaxPages 1 } $script:base } |
            Should -Throw '*page limit*'
    }

    It 'does not return partial data when a later page is inaccessible' {
        Connect-GHGovernance -Enterprise example -Token 'fixture' -ApiBaseUrl $script:base | Out-Null
        try {
            $result = & $script:module { Invoke-GitHubRest -Path 'unavailable' -Paginate -StrictErrors }
            $result.Ok | Should -BeFalse
            $result.Status | Should -Be 403
            $result.Data | Should -BeNullOrEmpty
            { & $script:module { Invoke-GitHubRest -Path 'foreign' -Paginate -StrictErrors } } |
                Should -Throw '*different pagination origin*'
        } finally {
            Disconnect-GHGovernance
        }
    }
}
