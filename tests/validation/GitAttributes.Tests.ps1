BeforeAll {
    Import-Module "$PSScriptRoot/../../src/GitHubGovernance/GitHubGovernance.psd1" -Force
}

Describe 'Root file lookup HTTP errors' {
    BeforeEach {
        Mock Get-InstallationToken -ModuleName GitHubGovernance { 'fixture-token' }
        Connect-GHGovernance -Enterprise 'example' -AppClientId 'client' -AppPrivateKey 'unused' -ApiBaseUrl 'https://api.example.test' | Out-Null
        Mock Invoke-RestMethod -ModuleName GitHubGovernance {
            if ($Uri -match '/git/trees/') {
                $response = [System.Net.Http.HttpResponseMessage]::new([System.Net.HttpStatusCode]$script:treeErrorStatus)
                throw [Microsoft.PowerShell.Commands.HttpResponseException]::new('Git Repository is empty.', $response)
            }
            [pscustomobject]@{ archived = $false; default_branch = 'main' }
        }
    }

    AfterEach { Disconnect-GHGovernance }

    It '<checkId> remains unevaluated for an empty repository rather than aborting' -ForEach @(
        @{ checkId = 'repo.gitattributes-present' }
        @{ checkId = 'repo.gitignore-present' }
        @{ checkId = 'repo.readme-present' }
    ) {
        $script:treeErrorStatus = 409
        (Invoke-GHComplianceCheck -CheckId $checkId -Organization 'org-a' -Repository 'repo-a').status | Should -Be 'na'
    }

    It 'keeps empty repository snapshot evidence unevaluated' {
        $script:treeErrorStatus = 409
        $evidence = & (Get-Module GitHubGovernance) {
            Get-GHRootFileEvidence -Organization 'org-a' -Repository 'repo-a' -DefaultBranch 'main'
        }
        $evidence.gitAttributes.evaluated | Should -BeFalse
        $evidence.gitIgnore.evaluated | Should -BeFalse
        $evidence.readme.evaluated | Should -BeFalse
    }

    It 'still propagates other unexpected HTTP errors in live checks' {
        $script:treeErrorStatus = 500
        { Invoke-GHComplianceCheck -CheckId 'repo.readme-present' -Organization 'org-a' -Repository 'repo-a' } |
            Should -Throw
    }
}

Describe 'Repository root file presence: <fileName>' -ForEach @(
    @{ checkId = 'repo.gitattributes-present'; fileName = '.gitattributes' }
    @{ checkId = 'repo.gitignore-present'; fileName = '.gitignore' }
    @{ checkId = 'repo.readme-present'; fileName = 'README.md' }
) {
    BeforeEach {
        Mock Get-InstallationToken -ModuleName GitHubGovernance { 'fixture-token' }
        Connect-GHGovernance -Enterprise 'example' -AppClientId 'client' -AppPrivateKey 'unused' -ApiBaseUrl 'https://api.example.test' | Out-Null
        $script:attributesStatus = 200
        $script:archived = $false
        $script:attributesTree = [pscustomobject]@{
            truncated = $false
            tree = @([pscustomobject]@{ path = $fileName; type = 'blob'; mode = '100644' })
        }
        Mock Invoke-GitHubRest -ModuleName GitHubGovernance {
            if ($Path -match '/git/trees/') {
                return [pscustomobject]@{
                    Ok = ($script:attributesStatus -eq 200); Status = $script:attributesStatus; Data = $script:attributesTree
                }
            }
            return [pscustomobject]@{
                Ok = $true; Status = 200
                Data = [pscustomobject]@{ archived = $script:archived; default_branch = 'release/main' }
            }
        }
    }

    AfterEach { Disconnect-GHGovernance }

    It 'passes for a regular root file and escapes the default branch name' {
        (Invoke-GHComplianceCheck -CheckId $checkId -Organization 'org-a' -Repository 'repo-a').status | Should -Be 'pass'
        Should -Invoke Invoke-GitHubRest -ModuleName GitHubGovernance -Times 1 -Exactly -ParameterFilter {
            $Path -eq 'repos/org-a/repo-a/git/trees/release%2Fmain' -and $StrictErrors
        }
    }

    It 'fails when the root file is absent' {
        $script:attributesTree.tree = @()
        (Invoke-GHComplianceCheck -CheckId $checkId -Organization 'org-a' -Repository 'repo-a').status | Should -Be 'fail'
    }

    It 'does not accept a directory, symlink or incorrectly cased name' -ForEach @(
        @{ type = 'tree'; mode = '040000'; uppercase = $false }
        @{ type = 'blob'; mode = '120000'; uppercase = $false }
        @{ type = 'blob'; mode = '100644'; uppercase = $true }
    ) {
        $path = if ($uppercase) { $fileName.ToUpperInvariant() } else { $fileName }
        $script:attributesTree.tree = @([pscustomobject]@{ path = $path; type = $type; mode = $mode })
        (Invoke-GHComplianceCheck -CheckId $checkId -Organization 'org-a' -Repository 'repo-a').status | Should -Be 'fail'
    }

    It 'does not turn denied or ambiguous requests into findings' -ForEach @(403, 404) {
        $script:attributesStatus = $_
        (Invoke-GHComplianceCheck -CheckId $checkId -Organization 'org-a' -Repository 'repo-a').status | Should -Be 'na'
    }

    It 'does not evaluate incomplete tree data' -ForEach @('truncated', 'missing-tree') {
        if ($_ -eq 'truncated') {
            $script:attributesTree.truncated = $true
        } else {
            $script:attributesTree.PSObject.Properties.Remove('tree')
        }
        (Invoke-GHComplianceCheck -CheckId $checkId -Organization 'org-a' -Repository 'repo-a').status | Should -Be 'na'
    }

    It 'excludes archived repositories without collecting tree data' {
        $script:archived = $true
        (Invoke-GHComplianceCheck -CheckId $checkId -Organization 'org-a' -Repository 'repo-a').status | Should -Be 'na'
        Should -Invoke Invoke-GitHubRest -ModuleName GitHubGovernance -Times 0 -Exactly -ParameterFilter { $Path -match '/git/trees/' }
    }

    It 'does not treat older snapshots without collection evidence as compliant' {
        $result = & (Get-Module GitHubGovernance) {
            param($path)
            $check = & $path -PolicyOnly
            & $check ([pscustomobject]@{ name = 'repo-a' }) $null $null $null
        } "$PSScriptRoot/../$checkId/$checkId.Tests.ps1"
        $result.status | Should -Be 'na'
    }

    It 'does not accept only a nested file' {
        $script:attributesTree.tree = @([pscustomobject]@{ path = "src/$fileName"; type = 'blob'; mode = '100644' })
        (Invoke-GHComplianceCheck -CheckId $checkId -Organization 'org-a' -Repository 'repo-a').status | Should -Be 'fail'
    }

    It 'reuses the tree lookup across root file checks' {
        $cache = @{}
        Invoke-GHComplianceCheck -CheckId 'repo.gitattributes-present' -Organization 'org-a' -Repository 'repo-a' -DataCache $cache | Out-Null
        Invoke-GHComplianceCheck -CheckId 'repo.gitignore-present' -Organization 'org-a' -Repository 'repo-a' -DataCache $cache | Out-Null
        Invoke-GHComplianceCheck -CheckId 'repo.readme-present' -Organization 'org-a' -Repository 'repo-a' -DataCache $cache | Out-Null
        Should -Invoke Invoke-GitHubRest -ModuleName GitHubGovernance -Times 1 -Exactly -ParameterFilter { $Path -match '/git/trees/' }
    }
}
