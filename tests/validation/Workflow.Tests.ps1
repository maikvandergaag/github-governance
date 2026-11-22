BeforeAll {
    Import-Module "$PSScriptRoot/../../src/GitHubGovernance/GitHubGovernance.psd1" -Force
    $workflow = Get-Content "$PSScriptRoot/../../.github/workflows/document-enterprise.yml" -Raw
    $validate = [regex]::Match($workflow, '(?ms)^  validate:\r?\n.*?(?=^  inventory:)').Value
    $inventory = [regex]::Match($workflow, '(?ms)^  inventory:\r?\n.*?(?=^  pester:)').Value
    $pester = [regex]::Match($workflow, '(?ms)^  pester:\r?\n.*?(?=^  commit_docs:)').Value
    $commitDocs = [regex]::Match($workflow, '(?ms)^  commit_docs:\r?\n.*?(?=^  publish_sarif:)').Value
    $sarif = [regex]::Match($workflow, '(?ms)^  publish_sarif:\r?\n.*?(?=^  summarize:)').Value
    $summary = [regex]::Match($workflow, '(?ms)^  summarize:\r?\n.*?(?=^  sync-issues:)').Value
    $sync = [regex]::Match($workflow, '(?ms)^  sync-issues:\r?\n.*\z').Value
    function Get-WorkflowStepScript([string] $Name, [string] $Job = $validate) {
        $pattern = '(?ms)^      - name: ' + [regex]::Escape($Name) +
            '\r?\n.*?^        run: \|\r?\n(?<body>(?:^ {10}[^\r\n]*\r?\n)+)'
        $body = [regex]::Match($Job, $pattern).Groups['body'].Value
        if (-not $body) { throw "Workflow step not found: $Name" }
        return [scriptblock]::Create(($body -replace '(?m)^ {10}', ''))
    }
    function Get-BashStepScript([string] $Job, [string] $Name) {
        $pattern = '(?ms)^      - name: ' + [regex]::Escape($Name) +
            '\r?\n.*?^        run: \|\r?\n(?<body>(?:^ {10}[^\r\n]*\r?\n|^\r?\n)+)'
        $body = [regex]::Match($Job, $pattern).Groups['body'].Value
        if (-not $body) { throw "Workflow step not found: $Name" }
        return ($body -replace '(?m)^ {10}', '')
    }
    function Invoke-BashStep([string] $Path, [string] $Script) {
        Push-Location $Path
        try {
            & bash -c $Script
            if ($LASTEXITCODE -ne 0) { throw "Workflow step failed (exit $LASTEXITCODE)." }
        } finally { Pop-Location }
    }
    function Invoke-WorkflowStepFixture([scriptblock] $Script, [hashtable] $Overrides = @{}) {
        $values = @{
            ACCOUNT_SCOPE = 'enterprise'; ENTERPRISE_SLUG = 'example'; ACCOUNT_LOGIN = 'alice'
            GH_APP_CLIENT_ID = 'client'; GH_APP_PRIVATE_KEY = 'fixture-key'; GITHUB_TOKEN = 'fixture-token'
            ENTERPRISE_API_URL = 'https://api.github.com'
            RUN_DOCUMENTATION = 'true'; RUN_COMPLIANCE = 'true'; RUN_SARIF = 'true'
            DOCS_PUBLISH_MODE = 'pull_request'
            MODULE_PATH = './src/GitHubGovernance/GitHubGovernance.psd1'
        }
        foreach ($key in $Overrides.Keys) { $values[$key] = $Overrides[$key] }
        $previous = @{}
        foreach ($key in $values.Keys) {
            $previous[$key] = [Environment]::GetEnvironmentVariable($key)
            [Environment]::SetEnvironmentVariable($key, $values[$key])
        }
        try { & $Script }
        finally {
            foreach ($key in $values.Keys) {
                [Environment]::SetEnvironmentVariable($key, $previous[$key])
            }
        }
    }
}

Describe 'Compliance workflow stages' {
    It 'offers manual account mode selection and preserves the scheduled mode fallback' {
        $workflow | Should -Match '(?ms)workflow_dispatch:\r?\n    inputs:\r?\n      mode:\r?\n.*?        type: choice\r?\n.*?        default: enterprise\r?\n        options:\r?\n          - enterprise\r?\n          - organization\r?\n          - user'
        $workflow | Should -Match 'ACCOUNT_SCOPE: \$\{\{ inputs\.mode \|\| vars\.ACCOUNT_SCOPE \|\| ''enterprise'' \}\}'
        $validate | Should -Match 'switch \(\$env:ACCOUNT_SCOPE\)'
        $sync | Should -Match '-Scope \$env:ACCOUNT_SCOPE'
    }

    It 'defaults all three manual and scheduled actions to enabled' {
        foreach ($name in 'documentation', 'compliance', 'publish_sarif') {
            $workflow | Should -Match ("(?ms)^      ${name}:\r?\n.*?        type: boolean\r?\n        default: true")
            $workflow | Should -Match ("github\.event_name == 'schedule' \|\| inputs\.$name")
        }
    }

    It 'validates configuration before authenticating and collecting data' {
        $validate.IndexOf('- name: Validate configuration') | Should -BeLessThan $validate.IndexOf('- name: Validate GitHub App authentication')
        $validate | Should -Not -Match 'Generate documentation'
        $inventory | Should -Match '(?m)^    needs: validate\r?$'
        $script = Get-WorkflowStepScript 'Validate configuration'
        { Invoke-WorkflowStepFixture $script } | Should -Not -Throw
        { Invoke-WorkflowStepFixture $script @{ ENTERPRISE_SLUG = ''; GH_APP_PRIVATE_KEY = '' } } |
            Should -Throw '*ENTERPRISE_SLUG*GH_APP_PRIVATE_KEY*'
        { Invoke-WorkflowStepFixture $script @{ ACCOUNT_SCOPE = 'user'; ACCOUNT_LOGIN = '' } } |
            Should -Throw '*ACCOUNT_LOGIN*'
        { Invoke-WorkflowStepFixture $script @{ GH_APP_CLIENT_ID = ''; GITHUB_TOKEN = '' } } |
            Should -Throw '*GH_APP_CLIENT_ID*GITHUB_TOKEN*'
        { Invoke-WorkflowStepFixture $script @{ ENTERPRISE_API_URL = 'http://example.test' } } |
            Should -Throw '*HTTPS URL*'
        { Invoke-WorkflowStepFixture $script @{ ACCOUNT_SCOPE = 'invalid' } } |
            Should -Throw '*Invalid account mode*'
        { Invoke-WorkflowStepFixture $script @{ DOCS_PUBLISH_MODE = 'invalid' } } |
            Should -Throw '*DOCS_PUBLISH_MODE*'
        { Invoke-WorkflowStepFixture $script @{ RUN_COMPLIANCE = 'false'; RUN_SARIF = 'true' } } |
            Should -Throw '*requires compliance tests*'
        { Invoke-WorkflowStepFixture $script @{ RUN_DOCUMENTATION = 'false'; RUN_COMPLIANCE = 'false'; RUN_SARIF = 'false'; GH_APP_PRIVATE_KEY = '' } } |
            Should -Not -Throw
    }

    It 'validates the action combination docs=<Docs> compliance=<Compliance> SARIF=<Sarif>' -TestCases @(
        @{ Docs = 'false'; Compliance = 'false'; Sarif = 'false' }
        @{ Docs = 'false'; Compliance = 'false'; Sarif = 'true' }
        @{ Docs = 'false'; Compliance = 'true'; Sarif = 'false' }
        @{ Docs = 'false'; Compliance = 'true'; Sarif = 'true' }
        @{ Docs = 'true'; Compliance = 'false'; Sarif = 'false' }
        @{ Docs = 'true'; Compliance = 'false'; Sarif = 'true' }
        @{ Docs = 'true'; Compliance = 'true'; Sarif = 'false' }
        @{ Docs = 'true'; Compliance = 'true'; Sarif = 'true' }
    ) {
        param($Docs, $Compliance, $Sarif)
        $options = @{
            RUN_DOCUMENTATION = $Docs; RUN_COMPLIANCE = $Compliance; RUN_SARIF = $Sarif
            GITHUB_OUTPUT = (Join-Path $TestDrive "selected-$Docs-$Compliance-$Sarif")
        }
        $config = Get-WorkflowStepScript 'Validate configuration'
        if ($Sarif -eq 'true' -and $Compliance -eq 'false') {
            { Invoke-WorkflowStepFixture $config $options } | Should -Throw '*requires compliance tests*'
        } else {
            { Invoke-WorkflowStepFixture $config $options } | Should -Not -Throw
            Invoke-WorkflowStepFixture (Get-WorkflowStepScript 'Record selected actions') $options
            $outputs = Get-Content $options.GITHUB_OUTPUT
            $outputs | Should -Contain "documentation=$Docs"
            $outputs | Should -Contain "compliance=$Compliance"
            $outputs | Should -Contain "sarif=$Sarif"
        }
    }

    It 'checks authentication against the selected account and disconnects' -TestCases @(
        @{ Mode = 'enterprise' }
        @{ Mode = 'organization' }
        @{ Mode = 'user' }
    ) {
        param($Mode)
        Mock Import-Module {}
        Mock Connect-GHGovernance {}
        Mock Get-GHOrganization {}
        Mock Get-GHRepository {}
        Mock Disconnect-GHGovernance {}
        $script = Get-WorkflowStepScript 'Validate GitHub App authentication'
        Invoke-WorkflowStepFixture $script @{ ACCOUNT_SCOPE = $Mode }
        if ($Mode -eq 'enterprise') {
            Should -Invoke Connect-GHGovernance -Times 1 -ParameterFilter { $Enterprise -eq 'example' -and $AppClientId -eq 'client' }
        } elseif ($Mode -eq 'organization') {
            Should -Invoke Connect-GHGovernance -Times 1 -ParameterFilter { $Organization -eq 'alice' -and $AppClientId -eq 'client' }
        } else {
            Should -Invoke Connect-GHGovernance -Times 1 -ParameterFilter { $User -eq 'alice' -and $AppClientId -eq 'client' }
        }
        Should -Invoke Disconnect-GHGovernance -Times 1
        if ($Mode -eq 'user') {
            Should -Invoke Get-GHRepository -Times 1 -ParameterFilter { $Organization -eq 'alice' -and $IncludeArchived }
            Should -Invoke Get-GHOrganization -Times 0
        } else {
            Should -Invoke Get-GHOrganization -Times 1
            Should -Invoke Get-GHRepository -Times 0
        }
    }

    It 'fails and disconnects when account access cannot be verified' {
        Mock Import-Module {}
        Mock Connect-GHGovernance {}
        Mock Get-GHOrganization { throw 'Access denied' }
        Mock Disconnect-GHGovernance {}
        $script = Get-WorkflowStepScript 'Validate GitHub App authentication'
        { Invoke-WorkflowStepFixture $script } | Should -Throw '*Access denied*'
        Should -Invoke Disconnect-GHGovernance -Times 1
    }

    It 'pins every external action to a full commit SHA' {
        $actions = [regex]::Matches($workflow, '(?m)^\s*uses:\s*(\S+)')
        $actions.Count | Should -BeGreaterThan 0
        foreach ($action in $actions) {
            $action.Groups[1].Value | Should -Match '^[^@]+@[0-9a-f]{40}$'
        }
    }

    It 'runs inventory for documentation or compliance and gates downstream jobs' {
        $inventory | Should -Match 'needs\.validate\.outputs\.documentation == ''true'' \|\| needs\.validate\.outputs\.compliance == ''true'''
        $inventory | Should -Match '(?m)^      - name: Collect documentation and inventory\r?$'
        $pester | Should -Match '(?m)^    needs: \[validate, inventory\]\r?$'
        $pester | Should -Match 'needs\.validate\.outputs\.compliance == ''true'''
        $pester | Should -Match '(?m)^      - name: Evaluate compliance with Pester\r?$'
        $commitDocs | Should -Match 'needs\.validate\.outputs\.documentation == ''true'''
        $commitDocs | Should -Match 'needs\.validate\.outputs\.compliance != ''true'' \|\| needs\.pester\.result == ''success'''
        $sarif | Should -Match 'needs\.validate\.outputs\.sarif == ''true'''
        $sarif | Should -Match 'needs\.validate\.outputs\.documentation != ''true'' \|\| needs\.commit_docs\.result == ''success'''
        $summary | Should -Match 'needs\.validate\.outputs\.sarif == ''false'''
        $sync | Should -Match 'needs\.validate\.outputs\.compliance == ''true'''
        $sync | Should -Not -Match 'needs:.*commit_docs'
        $sync | Should -Match '(?m)^      - name: Sync compliance issues\r?$'
    }

    It 'transfers findings and a patch that includes documentation deletions' {
        $inventory | Should -Match 'git diff --cached --binary -- "\$OUTPUT_PATH" > generated-docs\.patch'
        $inventory | Should -Match '(?m)^\s+name: documentation-patch\r?$'
        $pester | Should -Match '(?m)^\s+name: documentation-patch\r?$'
        $pester | Should -Match 'git apply --index --whitespace=nowarn generated-docs\.patch'
        $pester | Should -Match 'git add -A "\$OUTPUT_PATH"'
        $pester | Should -Match 'git diff --cached --binary -- "\$OUTPUT_PATH" > enterprise-docs\.patch'
        $pester | Should -Match '(?m)^\s+name: compliance-findings\r?$'
        $pester | Should -Match '(?m)^\s+compliance-findings\.json\r?$'
        $pester | Should -Match '(?m)^\s+enterprise-docs\.patch\r?$'
        $commitDocs | Should -Match 'git apply --index --whitespace=nowarn "\$patch"'
        $commitDocs | Should -Match '(?m)^\s+name: compliance-findings\r?$'
        $commitDocs | Should -Match '(?m)^\s+name: documentation-patch\r?$'
        $sync | Should -Match '(?m)^\s+name: compliance-findings\r?$'
    }

    It 'transfers generated changes through Pester to the publishing checkout' {
        $source = Join-Path $TestDrive 'source'
        $evaluation = Join-Path $TestDrive 'evaluation'
        $destination = Join-Path $TestDrive 'destination'
        New-Item -ItemType Directory -Path "$source/docs/output" -Force | Out-Null
        & git -C $source init -q
        Set-Content "$source/docs/output/changed.md" 'old'
        Set-Content "$source/docs/output/removed.md" 'old'
        New-Item -ItemType Directory -Path "$source/docs/output/compliance" | Out-Null
        Set-Content "$source/docs/output/compliance/README.md" 'old report'
        & git -C $source add .
        & git -C $source -c user.name=Fixture -c user.email=fixture@example.invalid commit -qm fixture
        if ($LASTEXITCODE -ne 0) {
            throw 'Could not create the workflow test fixture.'
        }
        & git clone -q $source $destination
        if ($LASTEXITCODE -ne 0) {
            throw 'Could not clone the workflow test fixture.'
        }
        & git clone -q $source $evaluation
        if ($LASTEXITCODE -ne 0) { throw 'Could not clone the Pester test fixture.' }
        Set-Content "$source/docs/output/changed.md" 'new'
        Remove-Item "$source/docs/output/removed.md"
        Set-Content "$source/docs/output/added.md" 'added'
        $previousOutputPath = $env:OUTPUT_PATH
        try {
            $env:OUTPUT_PATH = 'docs/output'
            Invoke-BashStep $source (Get-BashStepScript $inventory 'Prepare documentation patch')
            Copy-Item "$source/generated-docs.patch" "$evaluation/generated-docs.patch"
            Invoke-BashStep $evaluation (Get-BashStepScript $pester 'Restore documentation')
            Get-Content "$evaluation/docs/output/added.md" | Should -Be 'added'
            Test-Path "$evaluation/docs/output/removed.md" | Should -BeFalse
            Set-Content "$evaluation/docs/output/compliance/README.md" 'new report'
            Set-Content "$evaluation/compliance-findings.json" '[]'
            Invoke-BashStep $evaluation (Get-BashStepScript $pester 'Prepare generated documentation')
        } finally {
            $env:OUTPUT_PATH = $previousOutputPath
        }
        & git -C $destination apply --index --whitespace=nowarn "$evaluation/enterprise-docs.patch"
        $LASTEXITCODE | Should -Be 0
        Get-Content "$destination/docs/output/changed.md" | Should -Be 'new'
        Get-Content "$destination/docs/output/added.md" | Should -Be 'added'
        Test-Path "$destination/docs/output/removed.md" | Should -BeFalse
        Get-Content "$destination/docs/output/compliance/README.md" | Should -Be 'new report'
    }

    It 'accepts an empty documentation patch' {
        Set-Content -Path "$TestDrive/generated-docs.patch" -Value '' -NoNewline
        { Invoke-BashStep $TestDrive (Get-BashStepScript $pester 'Restore documentation') } | Should -Not -Throw
    }

    It 'commits the correct patch when compliance is <Mode>' -TestCases @(
        @{ Mode = 'false'; ExpectedReport = 'old report' }
        @{ Mode = 'true'; ExpectedReport = 'new report' }
    ) {
        param($Mode, $ExpectedReport)
        $source = Join-Path $TestDrive "source-$Mode"
        $remote = Join-Path $TestDrive "remote-$Mode.git"
        $destination = Join-Path $TestDrive "commit-$Mode"
        New-Item -ItemType Directory -Path "$source/docs/output/compliance" -Force | Out-Null
        & git -C $source init -q
        Set-Content "$source/docs/output/page.md" 'old page'
        Set-Content "$source/docs/output/compliance/README.md" 'old report'
        & git -C $source add .
        & git -C $source -c user.name=Fixture -c user.email=fixture@example.invalid commit -qm fixture
        & git clone --bare -q $source $remote
        & git clone -q $remote $destination
        if ($LASTEXITCODE -ne 0) { throw 'Could not create the commit test fixture.' }
        Set-Content "$source/docs/output/page.md" 'new page'

        $keys = @('OUTPUT_PATH', 'RUN_COMPLIANCE', 'DOCS_PUBLISH_MODE', 'GITHUB_OUTPUT', 'GITHUB_STEP_SUMMARY')
        $previous = @{}
        foreach ($key in $keys) { $previous[$key] = [Environment]::GetEnvironmentVariable($key) }
        try {
            $env:OUTPUT_PATH = 'docs/output'
            Invoke-BashStep $source (Get-BashStepScript $inventory 'Prepare documentation patch')
            Set-Content "$source/docs/output/compliance/README.md" 'new report'
            Set-Content "$source/compliance-findings.json" '[]'
            Invoke-BashStep $source (Get-BashStepScript $pester 'Prepare generated documentation')
            Copy-Item "$source/generated-docs.patch" "$destination/generated-docs.patch"
            Copy-Item "$source/enterprise-docs.patch" "$destination/enterprise-docs.patch"
            $env:RUN_COMPLIANCE = $Mode
            $env:DOCS_PUBLISH_MODE = 'direct'
            $env:GITHUB_OUTPUT = Join-Path $TestDrive "output-$Mode"
            $env:GITHUB_STEP_SUMMARY = Join-Path $TestDrive "summary-$Mode"
            Invoke-BashStep $destination (Get-BashStepScript $commitDocs 'Commit changes')
            Get-Content "$destination/docs/output/page.md" | Should -Be 'new page'
            Get-Content "$destination/docs/output/compliance/README.md" | Should -Be $ExpectedReport
            $sha = (& git -C $destination rev-parse HEAD).Trim()
            Get-Content $env:GITHUB_OUTPUT | Should -Contain "sha=$sha"
            @(Get-Content $env:GITHUB_OUTPUT)[-1] | Should -Be 'docs_committed=true'
        } finally {
            foreach ($key in $keys) { [Environment]::SetEnvironmentVariable($key, $previous[$key]) }
        }
    }

    It 'creates and updates a managed documentation branch without overwriting other work' {
        $source = Join-Path $TestDrive 'pr-source'
        $remote = Join-Path $TestDrive 'pr-remote.git'
        $destination = Join-Path $TestDrive 'pr-destination'
        $bin = Join-Path $TestDrive 'pr-bin'
        New-Item -ItemType Directory -Path "$source/docs/enterprise", $bin -Force | Out-Null
        & git -C $source init -q
        Set-Content "$source/docs/enterprise/page.md" 'old page'
        & git -C $source add .
        & git -C $source -c user.name=Fixture -c user.email=fixture@example.invalid commit -qm fixture
        & git clone --bare -q $source $remote
        & git clone -q $remote $destination
        if ($LASTEXITCODE -ne 0) { throw 'Could not create the PR test fixture.' }
        $base = (& git -C $source branch --show-current).Trim()
        $baseSha = (& git -C $source rev-parse HEAD).Trim()
        & git -C $destination checkout -q --detach $baseSha
        $gh = @'
#!/usr/bin/env bash
set -e
echo "$*" >> "$GH_CALLS"
case "$1 $2" in
  "pr list") if [ -f "$GH_PR" ]; then echo 42; fi ;;
  "pr view") echo '<!-- github-governance:managed-docs -->' ;;
  "pr create") touch "$GH_PR" ;;
  "pr close") rm "$GH_PR" ;;
  *) exit 1 ;;
esac
'@
        [IO.File]::WriteAllText("$bin/gh", $gh.Replace("`r`n", "`n") + "`n")
        & chmod +x "$bin/gh"
        $keys = @('PATH', 'OUTPUT_PATH', 'RUN_COMPLIANCE', 'DOCS_PUBLISH_MODE', 'GITHUB_REF_NAME', 'GITHUB_OUTPUT', 'GITHUB_STEP_SUMMARY', 'GH_CALLS', 'GH_PR')
        $previous = @{}
        foreach ($key in $keys) { $previous[$key] = [Environment]::GetEnvironmentVariable($key) }
        try {
            $env:PATH = "$bin$([IO.Path]::PathSeparator)$env:PATH"
            $env:OUTPUT_PATH = 'docs/enterprise'
            $env:RUN_COMPLIANCE = 'false'
            $env:DOCS_PUBLISH_MODE = 'pull_request'
            $env:GITHUB_REF_NAME = $base
            $env:GITHUB_OUTPUT = Join-Path $TestDrive 'pr-output'
            $env:GITHUB_STEP_SUMMARY = Join-Path $TestDrive 'pr-summary'
            $env:GH_CALLS = Join-Path $TestDrive 'pr-gh-calls'
            $env:GH_PR = Join-Path $TestDrive 'pr-open'
            $publish = Get-BashStepScript $commitDocs 'Commit changes'
            Set-Content "$source/docs/enterprise/page.md" 'first inventory'
            Invoke-BashStep $source (Get-BashStepScript $inventory 'Prepare documentation patch')
            Copy-Item "$source/generated-docs.patch" "$destination/generated-docs.patch"
            Invoke-BashStep $destination $publish
            $branchHash = (& bash -c 'printf %s "$GITHUB_REF_NAME" | git hash-object --stdin').Trim()
            $branch = "github-governance/docs-$branchHash"
            (& git --git-dir=$remote rev-parse "refs/heads/$base").Trim() | Should -Be $baseSha
            (& git --git-dir=$remote show "refs/heads/${branch}:docs/enterprise/page.md").Trim() | Should -Be 'first inventory'
            Get-Content $env:GITHUB_OUTPUT | Should -Contain 'docs_committed=false'
            @(Get-Content $env:GH_CALLS | Where-Object { $_ -like 'pr create*' }).Count | Should -Be 1

            & git -C $destination checkout -q --detach $baseSha
            Set-Content "$source/docs/enterprise/page.md" 'second inventory'
            Invoke-BashStep $source (Get-BashStepScript $inventory 'Prepare documentation patch')
            Copy-Item "$source/generated-docs.patch" "$destination/generated-docs.patch" -Force
            Invoke-BashStep $destination $publish
            (& git --git-dir=$remote show "refs/heads/${branch}:docs/enterprise/page.md").Trim() | Should -Be 'second inventory'
            @(Get-Content $env:GH_CALLS | Where-Object { $_ -like 'pr create*' }).Count | Should -Be 1

            & git -C $destination checkout -q --detach $baseSha
            [IO.File]::WriteAllText("$destination/generated-docs.patch", '')
            Invoke-BashStep $destination $publish
            @(Get-Content $env:GH_CALLS | Where-Object { $_ -like 'pr close 42*' }).Count | Should -Be 1

            & git -C $destination fetch -q origin "refs/heads/${branch}:refs/heads/fixture-branch"
            & git -C $destination checkout -q fixture-branch
            Set-Content "$destination/unrelated.txt" 'user work'
            & git -C $destination add unrelated.txt
            & git -C $destination -c user.name=User -c user.email=user@example.invalid commit -qm 'user change'
            & git -C $destination push -q origin "HEAD:refs/heads/$branch"
            & git -C $destination checkout -q --detach $baseSha
            Copy-Item "$source/generated-docs.patch" "$destination/generated-docs.patch" -Force
            { Invoke-BashStep $destination $publish } | Should -Throw '*Workflow step failed*'
            (& git --git-dir=$remote show "refs/heads/${branch}:unrelated.txt").Trim() | Should -Be 'user work'
        } finally {
            foreach ($key in $keys) { [Environment]::SetEnvironmentVariable($key, $previous[$key]) }
        }
    }

    It 'uploads SARIF against the committed docs or original commit' {
        $commitDocs | Should -Match 'echo "sha=\$\(git rev-parse HEAD\)" >> "\$GITHUB_OUTPUT"'
        $sarif | Should -Match 'sha: \$\{\{ needs\.commit_docs\.outputs\.sha \|\| github\.sha \}\}'
        $sarif | Should -Match 'UsePolicyLocations:'
        $sarif | Should -Match 'DOCS_COMMITTED: \$\{\{ needs\.commit_docs\.outputs\.docs_committed \}\}'
        $sarif | Should -Match '(?m)^\s+name: compliance-sarif\r?$'
        $sarif | Should -Match 'results were uploaded to Security > Code scanning'
    }

    It 'writes findings to the summary when SARIF is not selected' {
        $findings = @(
            @{ id = 'org/repo'; failures = @(@{ check = 'repo.not-public'; severity = 'high' }); notEvaluated = @(@{ check = 'repo.stale' }) }
            @{ id = 'org'; failures = @(); notEvaluated = @() }
        )
        $findings | ConvertTo-Json -Depth 10 -AsArray | Set-Content "$TestDrive/compliance-findings.json"
        $summaryPath = Join-Path $TestDrive 'summary.md'
        $script = Get-WorkflowStepScript 'Summarize compliance' $summary
        Push-Location $TestDrive
        try {
            Invoke-WorkflowStepFixture $script @{ RUN_COMPLIANCE = 'true'; GITHUB_STEP_SUMMARY = $summaryPath }
        } finally { Pop-Location }
        $text = Get-Content $summaryPath -Raw
        $text | Should -Match '\| Targets evaluated \| 2 \|'
        $text | Should -Match '\| Failed checks \| 1 \|'
        $text | Should -Match '\| Checks not evaluated \| 1 \|'
        $text | Should -Match 'repo\.not-public'
    }

    It 'reports when neither compliance nor SARIF was selected' {
        $summaryPath = Join-Path $TestDrive 'summary-empty.md'
        $script = Get-WorkflowStepScript 'Summarize compliance' $summary
        Invoke-WorkflowStepFixture $script @{ RUN_COMPLIANCE = 'false'; GITHUB_STEP_SUMMARY = $summaryPath }
        Get-Content $summaryPath -Raw | Should -Match 'Compliance tests were not selected'
    }

    It 'points SARIF to committed policy when documentation is not published' {
        $finding = [pscustomobject]@{
            id = 'org/repo'; type = 'repo'; org = 'org'; repo = 'repo'; docs = 'docs/output/organizations/org/repositories.md'
            failures = @([pscustomobject]@{
                    check = 'repo.not-public'; severity = 'high'; title = 'Repository is private'
                    detail = 'Repository is public'; remediation = 'Make it private.'
                })
        }
        $output = Join-Path $TestDrive 'test.sarif'
        ConvertTo-GHComplianceSarif -Findings @($finding) -OutputFile $output -UsePolicyLocations -ServerUrl 'https://github.com' -Repository 'owner/docs' -Commit 'abc' 6>$null
        $result = (Get-Content $output -Raw | ConvertFrom-Json).runs[0].results[0]
        $result.locations[0].physicalLocation.artifactLocation.uri | Should -Be 'compliance/policy.json'
        $line = $result.locations[0].physicalLocation.region.startLine
        (Get-Content './compliance/policy.json')[$line - 1] | Should -Match '"repo\.not-public"'
        $result.message.text | Should -Match 'Policy definition:'
        $result.message.text | Should -Not -Match 'Generated documentation:'
    }
}
