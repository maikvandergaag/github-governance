# GitHubGovernance: document a GitHub Enterprise Cloud environment and evaluate it against a compliance policy.
Set-StrictMode -Version Latest

# Module-scoped connection state (set by Connect-GHGovernance).
$script:Connection = $null
$script:TokenCache = @{}
$script:LastGraphQLErrorPaths = @()

foreach ($folder in 'Private', 'Public') {
    foreach ($file in Get-ChildItem -Path (Join-Path $PSScriptRoot $folder) -Filter '*.ps1' | Sort-Object Name) {
        . $file.FullName
    }
}

Export-ModuleMember -Function (Get-ChildItem -Path (Join-Path $PSScriptRoot 'Public') -Filter '*.ps1').BaseName
