function Export-GHDocumentation {
    <#
    .SYNOPSIS
        Collects the enterprise and all organizations and writes the Markdown documentation
        plus raw JSON snapshots.

    .DESCRIPTION
        Layout under -OutputPath:
          README.md                                  index
          enterprise/<page>.md                       enterprise configuration
          organizations/<org>/<page>.md              one folder per organization, one page per topic
          compliance/README.md                       findings report (written by Test-GHCompliance, left alone here)
          _data/enterprise.json                      raw enterprise snapshot
          _data/organizations/<org>.json             raw organization snapshots

    .EXAMPLE
        Connect-GHGovernance -Enterprise contoso
        Export-GHDocumentation -OutputPath ./docs/enterprise
    #>
    [CmdletBinding()]
    param(
        [string] $OutputPath = './docs/enterprise',
        # Limit the run to these organizations (useful for testing).
        [string[]] $Organization,
        [switch] $SkipRepositories,
        [switch] $SkipCodeOwners
    )
    Assert-GHConnection

    $scope = $script:Connection.Scope
    $enterpriseInfo = $null
    $enterpriseSnap = $null
    if ($scope -eq 'enterprise') {
        Write-Host "Reading enterprise '$($script:Connection.Enterprise)' from $($script:ApiBaseUrl) (auth: $($script:AuthMode)) ..."
        $enterpriseInfo = Get-EnterpriseInfo
        $orgLogins = @($enterpriseInfo.Organizations | ForEach-Object login)
        if ($Organization) {
            $orgLogins = @($orgLogins | Where-Object { $_ -in $Organization })
        }
        Write-Host '  Collecting enterprise configuration ...'
        $enterpriseSnap = Get-GHEnterpriseConfiguration
    } else {
        if ($Organization -and ($scope -ne 'organization' -or @($Organization).Count -ne 1 -or $Organization[0] -ne $script:Connection.Account)) {
            throw '-Organization must match the connected organization.'
        }
        $orgLogins = @($script:Connection.Account)
    }
    Write-Host "Found $($orgLogins.Count) account(s)."

    $entDir = Join-Path $OutputPath 'enterprise'
    $orgRoot = Join-Path $OutputPath 'organizations'
    $dataDir = Join-Path $OutputPath '_data'
    $orgDataDir = Join-Path $dataDir 'organizations'
    # Regenerate from scratch so removed organizations/pages disappear (compliance/ is left alone).
    foreach ($dir in @($entDir, $orgRoot, $dataDir)) {
        if (Test-Path $dir) {
            Remove-Item $dir -Recurse -Force
        }
    }
    foreach ($dir in @($OutputPath, $entDir, $orgRoot, $orgDataDir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $snapshots = foreach ($org in $orgLogins) {
        Write-Host "  Collecting $org ..."
        if ($scope -eq 'user') {
            if ($script:AuthMode -ne 'App') {
                throw 'Personal account documentation requires a GitHub App connection.'
            }
            $repos = $null
            $owners = $null
            if (-not $SkipRepositories) {
                $repos = Invoke-GitHubRest 'installation/repositories' -Paginate -ItemProperty 'repositories' -StrictErrors
                if (-not $repos.Ok) {
                    throw "Cannot list repositories for $org (HTTP $($repos.Status))."
                }
                $repos.Data = @(foreach ($item in @($repos.Data | Where-Object { $_.owner.login -eq $org })) {
                    $detail = Invoke-GitHubRest "repos/$org/$($item.name)" -StrictErrors
                    if (-not $detail.Ok -or -not $detail.Data) {
                        throw "Cannot read repository $org/$($item.name) (HTTP $($detail.Status))."
                    }
                    if (-not (Get-Prop $detail.Data 'archived')) {
                        $evidence = Get-GHBranchEvidence -Organization ([uri]::EscapeDataString($org)) `
                            -Repository ([uri]::EscapeDataString($item.name)) -DefaultBranch (Get-Prop $detail.Data 'default_branch')
                        $detail.Data | Add-Member -NotePropertyName complianceBranchEvidence -NotePropertyValue $evidence -Force
                        $rootFiles = Get-GHRootFileEvidence -Organization ([uri]::EscapeDataString($org)) `
                            -Repository ([uri]::EscapeDataString($item.name)) -DefaultBranch (Get-Prop $detail.Data 'default_branch')
                        $detail.Data | Add-Member -NotePropertyName complianceGitAttributes -NotePropertyValue (Get-Prop $rootFiles 'gitAttributes') -Force
                        $detail.Data | Add-Member -NotePropertyName complianceGitIgnore -NotePropertyValue (Get-Prop $rootFiles 'gitIgnore') -Force
                        $detail.Data | Add-Member -NotePropertyName complianceReadme -NotePropertyValue (Get-Prop $rootFiles 'readme') -Force
                    }
                    $detail.Data
                })
                if (-not $SkipCodeOwners) {
                    $active = @($repos.Data | Where-Object { -not $_.archived } | ForEach-Object name)
                    $owners = @(Get-CodeOwnersBatch -Org $org -Repositories $active)
                }
            }
            $snap = [pscustomobject]@{ login = $org; accountType = 'user'; repositories = $repos; codeOwners = $owners }
        } else {
            $snap = Get-GHOrganizationConfiguration -Organization $org -SkipRepositories:$SkipRepositories -SkipCodeOwners:$SkipCodeOwners
        }
        $orgDir = Join-Path $orgRoot $org
        New-Item -ItemType Directory -Path $orgDir -Force | Out-Null
        $pages = if ($scope -eq 'user') { New-PersonalMarkdown -Snap $snap } else { New-OrganizationMarkdown -Snap $snap }
        foreach ($file in $pages.Keys) {
            $pages[$file] | Set-Content -Path (Join-Path $orgDir $file) -Encoding utf8NoBOM -NoNewline
        }
        $snap | ConvertTo-Json -Depth 20 | Set-Content -Path (Join-Path $orgDataDir "$org.json") -Encoding utf8NoBOM
        $snap
    }

    if ($scope -eq 'enterprise') {
        $enterpriseSnap | Add-Member -NotePropertyName name -NotePropertyValue $enterpriseInfo.Name -Force
        $enterpriseSnap | ConvertTo-Json -Depth 20 | Set-Content -Path (Join-Path $dataDir 'enterprise.json') -Encoding utf8NoBOM
        $entPages = New-EnterpriseConfigMarkdown -EnterpriseInfo $enterpriseInfo -Snap $enterpriseSnap
        foreach ($file in $entPages.Keys) {
            $entPages[$file] | Set-Content -Path (Join-Path $entDir $file) -Encoding utf8NoBOM -NoNewline
        }
    }

    $missingInstalls = @()
    if ($script:AuthMode -eq 'App') {
        $missingInstalls = @($script:TokenCache.Keys | Where-Object { $null -eq $script:TokenCache[$_].Token } | Sort-Object)
        if ($missingInstalls) {
            Write-Warning "GitHub App not installed on: $($missingInstalls -join ', ')"
        }
    }
    if ($scope -eq 'enterprise') {
        New-EnterpriseMarkdown -EnterpriseInfo $enterpriseInfo -EnterpriseSnap $enterpriseSnap -Snapshots @($snapshots) -MissingInstallations $missingInstalls |
            Set-Content -Path (Join-Path $OutputPath 'README.md') -Encoding utf8NoBOM -NoNewline
    } else {
        @("# GitHub $scope`: $($script:Connection.Account)", '', "[Account documentation](organizations/$($script:Connection.Account)/README.md)", '', '[Compliance findings](compliance/README.md)', '') -join "`n" |
            Set-Content -Path (Join-Path $OutputPath 'README.md') -Encoding utf8NoBOM -NoNewline
    }

    Write-Host "Documentation written to $((Resolve-Path $OutputPath).Path)"
}
