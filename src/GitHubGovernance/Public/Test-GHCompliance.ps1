function Test-GHCompliance {
    <#
    .SYNOPSIS
        Evaluates enterprise/organization/repository compliance against a policy.

    .DESCRIPTION
        Reads <DataPath>/enterprise.json and <DataPath>/organizations/*.json (written by
        Export-GHDocumentation) to discover targets. By default, evaluates their snapshots;
        -UsePester instead runs the tests against live GitHub data using an active GitHub App
        connection and the central compliance policy. Checks are discovered from manifests under
        <TestsPath>; both modes use the policy logic in <TestsPath>/<check-id>/<check-id>.Tests.ps1.
        Returns one object per target
        (enterprise, organization, active repository) with its failures and the checks that could
        not be evaluated. Optionally writes the findings as JSON (-OutputFile) and a Markdown
        report (-ReportFile).

        Every check returns pass, fail or na (not evaluated: data missing, e.g. a permission).
        na never creates an issue and never closes an existing one.

    .EXAMPLE
        Test-GHCompliance -DataPath ./docs/output/_data | Where-Object { $_.failures }
    #>
    [CmdletBinding()]
    param(
        [string] $DataPath = './docs/output/_data',
        [string] $PolicyPath = './compliance/policy.json',
        [string] $OutputFile,
        # Repository-relative path of the generated docs, used for links in issues/report/SARIF.
        [string] $DocsPath = 'docs/output',
        [string] $ReportFile,
        [switch] $UsePester,
        [string] $TestsPath = (Join-Path $PSScriptRoot '../../../tests'),
        [switch] $SkipCodeOwners
    )

    function Get-RelativeDocLink {
        # Converts a repo-relative docs path into a link relative to the report's folder.
        param([string] $DocPath)
        return [System.IO.Path]::GetRelativePath($DocsPath + '/compliance', $DocPath).Replace('\', '/')
    }

    $policy = Get-Content $PolicyPath -Raw | ConvertFrom-Json
    $checks = Get-GHComplianceChecks -TestsPath $TestsPath
    $known = @($checks.enterprise.Keys) + @($checks.org.Keys) + @($checks.repo.Keys)
    foreach ($entry in $policy.checks.PSObject.Properties) {
        if ($entry.Value.enabled -and $entry.Name -notin $known) {
            throw "Unknown enabled compliance check: $($entry.Name)"
        }
    }
    $policy = Merge-GHCompliancePolicy -Policy $policy -Checks $checks
    if ($UsePester) {
        Assert-GHConnection
        if ($script:AuthMode -ne 'App') {
            throw 'Compliance tests require a GitHub App connection. Run Connect-GHGovernance with -AppClientId and -AppPrivateKey.'
        }
        Import-Module Pester -MinimumVersion 5.7.1 -MaximumVersion 5.99 -ErrorAction Stop
    }
    $targets = [System.Collections.Generic.List[object]]::new()
    $checkModules = @{}

    $enterpriseFile = Join-Path $DataPath 'enterprise.json'
    if ($UsePester -and (-not (Test-Path -LiteralPath (Join-Path $DataPath 'organizations') -PathType Container) -or
            ($script:Connection.Scope -eq 'enterprise' -and -not (Test-Path -LiteralPath $enterpriseFile -PathType Leaf)))) {
        throw "The generated enterprise snapshot or organization inventory is missing from $DataPath."
    }
    if ($UsePester -and $script:Connection.Scope -ne 'enterprise') {
        $files = @(Get-ChildItem (Join-Path $DataPath 'organizations') -Filter '*.json')
        if ((Test-Path -LiteralPath $enterpriseFile) -or $files.Count -ne 1 -or
            $files[0].BaseName -ne $script:Connection.Account) {
            throw 'Snapshot inventory does not match the connected account.'
        }
    }
    if (Test-Path $enterpriseFile) {
        $entSnap = Get-Content $enterpriseFile -Raw | ConvertFrom-Json -Depth 50
        if ($UsePester -and $entSnap.slug -ne $script:Connection.Enterprise) {
            throw "Snapshot enterprise '$($entSnap.slug)' does not match the connected enterprise '$($script:Connection.Enterprise)'."
        }
        Write-Host "Evaluating enterprise $($entSnap.slug) ..."
        $entId = "enterprise:$($entSnap.slug)"
        $entResult = if ($UsePester) {
            Invoke-GHPesterChecks -Checks $checks.enterprise -TargetId $entId -Policy $policy -TestsPath $TestsPath
        } else {
            Invoke-Checks -Checks $checks.enterprise -Arguments @(, $entSnap) -TargetId $entId -Policy $policy -TestsPath $TestsPath -CheckModules $checkModules
        }
        $targets.Add([ordered]@{
                id = $entId
                type = 'enterprise'
                org = $entSnap.slug
                repo = $null
                docs = "$DocsPath/enterprise/README.md"
                reposEvaluated = $false
                failures = $entResult.failures
                notEvaluated = $entResult.notEvaluated
            })
    }

    foreach ($file in Get-ChildItem (Join-Path $DataPath 'organizations') -Filter '*.json' -ErrorAction SilentlyContinue | Sort-Object Name) {
        $snap = Get-Content $file.FullName -Raw | ConvertFrom-Json -Depth 50
        $org = $snap.login
        if ($UsePester -and $script:Connection.Scope -ne 'enterprise' -and
            ($org -ne $script:Connection.Account -or
                (((Get-Prop $snap 'accountType') -eq 'user') -ne ($script:Connection.Scope -eq 'user')))) {
            throw 'Snapshot account type or login does not match the connection.'
        }
        Write-Host "Evaluating $org ..."

        $repos = Get-Section $snap 'repositories'
        $personal = (Get-Prop $snap 'accountType') -eq 'user'
        $orgResult = if ($personal) {
            @{ failures = @(); notEvaluated = @() }
        } elseif ($UsePester) {
            Invoke-GHPesterChecks -Checks $checks.org -TargetId $org -Organization $org -Policy $policy -TestsPath $TestsPath
        } else {
            Invoke-Checks -Checks $checks.org -Arguments @(, $snap) -TargetId $org -Policy $policy -TestsPath $TestsPath -CheckModules $checkModules
        }
        $targets.Add([ordered]@{
                id = $org
                type = $(if ($personal) { 'account' } else { 'org' })
                org = $org
                repo = $null
                docs = "$DocsPath/organizations/$org/README.md"
                # Lets the issue sync distinguish "repo was removed/archived" from "repo data not collected this run".
                reposEvaluated = ($null -ne $repos)
                failures = $orgResult.failures
                notEvaluated = $orgResult.notEvaluated
            })

        if ($null -eq $repos) {
            continue
        }
        $codeOwnersByRepo = @{}
        foreach ($co in @(Get-Prop $snap 'codeOwners')) {
            if ($co) {
                $codeOwnersByRepo[$co.repository] = $co
            }
        }

        foreach ($repo in @($repos | Where-Object { -not $_.archived } | Sort-Object name)) {
            $targetId = "$org/$($repo.name)"
            $codeOwners = if ($null -ne (Get-Prop $snap 'codeOwners')) {
                $codeOwnersByRepo[$repo.name]
            } else {
                $null
            }
            $repoResult = if ($UsePester) {
                Invoke-GHPesterChecks -Checks $checks.repo -TargetId $targetId -Organization $org -Repository $repo.name -Policy $policy -TestsPath $TestsPath -SkipCodeOwners:$SkipCodeOwners
            } else {
                Invoke-Checks -Checks $checks.repo -Arguments @($repo, $snap, $codeOwners) -TargetId $targetId -Policy $policy -TestsPath $TestsPath -CheckModules $checkModules
            }
            $targets.Add([ordered]@{
                    id = $targetId
                    type = 'repo'
                    org = $org
                    repo = $repo.name
                    docs = "$DocsPath/organizations/$org/repositories.md"
                    failures = $repoResult.failures
                    notEvaluated = $repoResult.notEvaluated
                })
        }
    }

    $failing = @($targets | Where-Object { $_.failures.Count -gt 0 })
    Write-Host "Evaluated $($targets.Count) target(s); $($failing.Count) non-compliant."

    if ($OutputFile) {
        $targets | ConvertTo-Json -Depth 10 -AsArray | Set-Content -Path $OutputFile -Encoding utf8NoBOM
    }

    if ($ReportFile) {
        $sevOrder = @{ high = 0; medium = 1; low = 2 }
        $allFailures = @($failing | ForEach-Object { $_.failures })
        $bySeverity = @('high', 'medium', 'low') | ForEach-Object { $sev = $_; @($allFailures | Where-Object { $_.severity -eq $sev }).Count }
        $r = [System.Collections.Generic.List[string]]::new()
        $r.Add('# Compliance findings')
        $r.Add('')
        $r.Add('[Overview](../README.md) · [Configuration handbook](../../configuration/README.md) · Policy: [`compliance/policy.json`](../../../compliance/policy.json)')
        $r.Add('')
        $r.Add('| Metric | Count |')
        $r.Add('| --- | --- |')
        $r.Add("| Targets evaluated | $($targets.Count) |")
        $r.Add("| Non-compliant targets | $($failing.Count) |")
        $r.Add("| Findings high / medium / low | $($bySeverity -join ' / ') |")
        $r.Add("| Checks not evaluated (missing data) | $(@($targets | ForEach-Object { $_.notEvaluated }).Count) |")
        $r.Add('')
        $r.Add('Issues are tracked with the `compliance` label; the same findings are in Security > Code scanning.')
        $r.Add('')

        # Per check: how widespread is each problem?
        $r.Add('## By requirement')
        $r.Add('')
        $r.Add('| Severity | Requirement | Check | Targets |')
        $r.Add('| --- | --- | --- | --- |')
        $allFailures | Group-Object { $_.check } | Sort-Object { $sevOrder[$_.Group[0].severity] }, { - $_.Count } | ForEach-Object {
            $r.Add("| $($_.Group[0].severity) | $($_.Group[0].title) | ``$($_.Name)`` | $($_.Count) |")
        }
        $r.Add('')

        # Per target
        foreach ($section in @(@('enterprise', 'Enterprise'), @('org', 'Organizations'), @('repo', 'Repositories'))) {
            $list = @($failing | Where-Object { $_.type -eq $section[0] } | Sort-Object id)
            if ($list.Count -eq 0) {
                continue
            }
            $r.Add("## $($section[1]) ($($list.Count))")
            $r.Add('')
            $r.Add('| Target | Severity | Findings |')
            $r.Add('| --- | --- | --- |')
            foreach ($t in $list) {
                $worst = @($t.failures | Sort-Object { $sevOrder[$_.severity] })[0].severity
                $checks = (@($t.failures | Sort-Object { $sevOrder[$_.severity] }, check) | ForEach-Object { "``$($_.check)``" }) -join ', '
                $r.Add("| [$($t.id)]($(Get-RelativeDocLink $t.docs)) | $worst | $checks |")
            }
            $r.Add('')
        }

        # Accepted deviations are part of the documentation too.
        $r.Add('## Exemptions')
        $r.Add('')
        $exemptions = @(if ($policy.PSObject.Properties['exemptions']) {
                $policy.exemptions.PSObject.Properties
            })
        if ($exemptions.Count -eq 0) {
            $r.Add('_None._')
        } else {
            $r.Add('| Target | Exempted checks |')
            $r.Add('| --- | --- |')
            foreach ($e in $exemptions | Sort-Object Name) {
                $checkList = (@($e.Value) | ForEach-Object { '`' + $_ + '`' }) -join ', '
                $r.Add("| $($e.Name) | $checkList |")
            }
        }
        $r.Add('')
        $r.Add('---')
        $r.Add('_Generated by Test-GitHubEnterpriseCompliance.ps1. Do not edit manually._')

        New-Item -ItemType Directory -Path (Split-Path $ReportFile) -Force | Out-Null
        ($r -join "`n") + "`n" | Set-Content -Path $ReportFile -Encoding utf8NoBOM -NoNewline
        Write-Host "Report written to $ReportFile"
    }

    return $targets.ToArray() | ForEach-Object { [pscustomobject]$_ }
}
