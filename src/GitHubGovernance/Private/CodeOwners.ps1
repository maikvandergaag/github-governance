function ConvertFrom-CodeOwners {
    <#
    .SYNOPSIS
        Parses CODEOWNERS text into rules: line number, pattern and owners.
    #>
    param([string] $Text)

    $lineNumber = 0
    foreach ($raw in ($Text -split "`r?`n")) {
        $lineNumber++
        $line = $raw.Trim()
        if (-not $line -or $line.StartsWith('#')) {
            continue
        }
        # Strip trailing comments (an unescaped '#' preceded by whitespace).
        $line = ($line -replace '(?<!\\)\s+#.*$', '').Trim()
        $tokens = @($line -split '\s+')
        [pscustomobject]@{
            line = $lineNumber
            pattern = $tokens[0]
            owners = @($tokens | Select-Object -Skip 1)
        }
    }
}

function Get-CodeOwnersBatch {
    <#
    .SYNOPSIS
        Fetches CODEOWNERS for a set of repositories. Uses batched GraphQL (25 repos per call) to read the
        three supported locations, then the REST codeowners/errors endpoint for repos that have a file.
    #>
    param(
        [Parameter(Mandatory)] [string] $Org,
        [string[]] $Repositories
    )

    # Same precedence GitHub uses: the first file found wins.
    $locations = [ordered]@{ github = '.github/CODEOWNERS'; root = 'CODEOWNERS'; docs = 'docs/CODEOWNERS' }
    $batchSize = 25
    $results = [System.Collections.Generic.List[object]]::new()

    for ($i = 0; $i -lt $Repositories.Count; $i += $batchSize) {
        $batch = @($Repositories[$i..([Math]::Min($i + $batchSize, $Repositories.Count) - 1)])
        $fragments = for ($j = 0; $j -lt $batch.Count; $j++) {
            $files = foreach ($key in $locations.Keys) {
                "$key`: object(expression: `"HEAD:$($locations[$key])`") { ... on Blob { text } }"
            }
            "r$j`: repository(owner: `$owner, name: `"$($batch[$j])`") { $($files -join ' ') }"
        }
        $query = "query(`$owner: String!) { $($fragments -join "`n") }"
        $script:LastGraphQLErrorPaths = @()
        $data = Invoke-GitHubGraphQL -Query $query -Variables @{ owner = $Org } -AllowPartial -Scope "org:$Org"

        for ($j = 0; $j -lt $batch.Count; $j++) {
            $repoData = Get-Prop $data "r$j"
            $path = $null; $text = $null
            $pathEvaluated = $null -ne $repoData -and
            @($script:LastGraphQLErrorPaths | Where-Object { $_ -eq "r$j" -or $_ -like "r$j.*" }).Count -eq 0
            foreach ($key in $locations.Keys) {
                if (-not $repoData -or -not $repoData.PSObject.Properties[$key]) {
                    $pathEvaluated = $false
                }
            }
            foreach ($key in $locations.Keys) {
                $blobText = Get-Prop $repoData "$key.text"
                if ($null -ne $blobText) {
                    $path = $locations[$key]; $text = $blobText; break
                }
            }

            $entry = [ordered]@{ repository = $batch[$j]; path = $path; pathEvaluated = $pathEvaluated; rules = @(); errors = @(); errorsEvaluated = $false }
            if ($pathEvaluated -and $path) {
                $entry.rules = @(ConvertFrom-CodeOwners -Text $text)
                $errors = Invoke-GitHubRest "repos/$Org/$($batch[$j])/codeowners/errors"
                if ($errors.Ok -and $errors.Data -and $errors.Data.PSObject.Properties['errors'] -and
                    $null -ne $errors.Data.PSObject.Properties['errors'].Value) {
                    $entry.errors = @(Get-Prop $errors.Data 'errors') | Where-Object { $_ }
                    $entry.errorsEvaluated = $true
                }
            }
            $results.Add([pscustomobject]$entry)
        }
    }
    return $results
}
