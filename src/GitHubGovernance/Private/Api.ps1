function Invoke-GHPaginatedRest {
    param(
        [Parameter(Mandatory)] [string] $Uri,
        [Parameter(Mandatory)] [hashtable] $Headers,
        [int] $MaxPages = 1000
    )

    $origin = [uri]$Uri
    $seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $next = $origin
    $pages = 0
    $responses = [System.Collections.Generic.List[object]]::new()
    while ($next) {
        if ($next.Scheme -ne $origin.Scheme -or $next.Host -ne $origin.Host -or
            $next.Port -ne $origin.Port -or $next.UserInfo) {
            throw "Refusing to send credentials to a different pagination origin: $($next.GetLeftPart([System.UriPartial]::Authority))"
        }
        if (-not $seen.Add($next.AbsoluteUri)) {
            throw "Pagination link cycle detected at $($next.AbsoluteUri)"
        }
        if (++$pages -gt $MaxPages) {
            throw "Pagination exceeded the $MaxPages page limit."
        }

        $responseHeaders = $null
        $response = Invoke-RestMethod -Uri $next.AbsoluteUri -Method Get -Headers $Headers `
            -ResponseHeadersVariable responseHeaders -ErrorAction Stop
        if ($null -ne $response) {
            $responses.Add($response)
        }

        $nextLinks = @()
        if ($responseHeaders -and $responseHeaders.ContainsKey('Link')) {
            foreach ($link in @($responseHeaders['Link'])) {
                $links = [regex]::Matches($link, '<([^>]+)>\s*((?:;\s*[^,]+)*)')
                if ($links.Count -eq 0) {
                    throw 'Invalid pagination Link header.'
                }
                foreach ($match in $links) {
                    $rel = [regex]::Match($match.Groups[2].Value, '(?:^|;)\s*rel\s*=\s*(?:"([^"]+)"|([^;\s,]+))')
                    if (-not $rel.Success) {
                        throw 'Pagination Link header is missing a relation.'
                    }
                    $relations = if ($rel.Groups[1].Success) {
                        $rel.Groups[1].Value
                    } else {
                        $rel.Groups[2].Value
                    }
                    if ('next' -in ($relations -split '\s+')) {
                        $nextLinks += $match.Groups[1].Value
                    }
                }
            }
        }
        if ($nextLinks.Count -gt 1) {
            throw 'Multiple next pagination links were returned.'
        }
        $next = if ($nextLinks.Count) {
            [uri]::new($next, $nextLinks[0])
        } else {
            $null
        }
    }
    return , $responses.ToArray()
}

function Invoke-GitHubRest {
    <#
    .SYNOPSIS
        Calls a GitHub REST endpoint. Returns a PSCustomObject with Ok/Status/Data.
        With -Paginate all pages are fetched (Link header) and items are flattened.
    #>
    param(
        [Parameter(Mandatory)] [string] $Path,
        [switch] $Paginate,
        # For paginated endpoints that wrap their items, e.g. { total_count, installations: [...] }
        [string] $ItemProperty,
        [switch] $StrictErrors
    )

    $uri = '{0}/{1}' -f $script:ApiBaseUrl.TrimEnd('/'), $Path.TrimStart('/')
    if ($Paginate) {
        $uri += ($(if ($uri.Contains('?')) {
                    '&'
                } else {
                    '?'
                }) + 'per_page=100')
    }

    $headers = Get-RequestHeaders -Scope (Get-ScopeForPath $Path)
    if ($null -eq $headers) {
        # App mode: the App is not installed on this organization/enterprise.
        return [pscustomobject]@{ Ok = $false; Status = -1; Data = $null }
    }

    $params = @{
        Uri = $uri
        Headers = $headers
        Method = 'Get'
    }
    try {
        if ($Paginate) {
            $response = Invoke-GHPaginatedRest -Uri $uri -Headers $headers
        } else {
            $response = Invoke-RestMethod @params -ErrorAction Stop
        }
    } catch {
        $status = $null
        if ($_.Exception.PSObject.Properties['Response'] -and $_.Exception.Response) {
            $status = [int]$_.Exception.Response.StatusCode
        }
        if ($StrictErrors -and $status -notin 403, 404) {
            throw
        }
        Write-Verbose "GET $Path failed: $status $($_.Exception.Message)"
        return [pscustomobject]@{ Ok = $false; Status = $status; Data = $null }
    }

    if ($Paginate) {
        # Flatten pages and optionally unwrap a named item list.
        $items = foreach ($page in @($response)) {
            if ($ItemProperty) {
                if ($page.PSObject.Properties[$ItemProperty] -and $null -ne $page.$ItemProperty) {
                    $page.$ItemProperty
                } else {
                    throw "Paginated response from $Path is missing '$ItemProperty'."
                }
            } else {
                $page
            }
        }
        return [pscustomobject]@{ Ok = $true; Status = 200; Data = @($items | Where-Object { $null -ne $_ }) }
    }

    return [pscustomobject]@{ Ok = $true; Status = 200; Data = $response }
}

function Invoke-GitHubGraphQL {
    param(
        [Parameter(Mandatory)] [string] $Query,
        [hashtable] $Variables = @{},
        # Return partial data instead of throwing when some fields fail (e.g. one inaccessible repo in a batch).
        [switch] $AllowPartial,
        # Which installation to use in App mode: 'enterprise' or 'org:<login>'.
        [string] $Scope = 'enterprise'
    )

    $headers = Get-RequestHeaders -Scope $Scope
    if ($null -eq $headers) {
        throw "No credential for scope '$Scope' (GitHub App not installed there)."
    }
    $body = @{ query = $Query; variables = $Variables } | ConvertTo-Json -Depth 10 -Compress
    $response = Invoke-RestMethod -Uri $script:GraphQLUrl -Headers $headers -Method Post -Body $body -ContentType 'application/json' -ErrorAction Stop
    if ($response.PSObject.Properties['errors'] -and $response.errors) {
        if ($AllowPartial -and $response.PSObject.Properties['data'] -and $response.data) {
            if (@($response.errors | Where-Object { -not $_.PSObject.Properties['path'] -or -not $_.path }).Count -gt 0) {
                throw "GraphQL error without a field path: $(($response.errors | ForEach-Object message) -join '; ')"
            }
            Write-Verbose "GraphQL partial errors: $(($response.errors | ForEach-Object message) -join '; ')"
            # Keep the failing field paths so consumers can tell "null" apart from "not readable".
            $script:LastGraphQLErrorPaths = @($response.errors | ForEach-Object {
                    if ($_.PSObject.Properties['path'] -and $_.path) {
                        ($_.path | Where-Object { $_ -is [string] }) -join '.'
                    }
                } | Where-Object { $_ })
            return $response.data
        }
        throw "GraphQL error: $(($response.errors | ForEach-Object message) -join '; ')"
    }
    return $response.data
}

function Get-EnterpriseOrganizations {
    param([Parameter(Mandatory)] [string] $Slug)

    $query = @'
query($slug: String!, $cursor: String) {
  enterprise(slug: $slug) {
    name
    slug
    createdAt
    organizations(first: 100, after: $cursor) {
      pageInfo { hasNextPage endCursor }
      nodes { login name }
    }
  }
}
'@
    $orgs = [System.Collections.Generic.List[object]]::new()
    $cursor = $null
    $enterpriseInfo = $null
    do {
        $data = Invoke-GitHubGraphQL -Query $query -Variables @{ slug = $Slug; cursor = $cursor }
        if (-not $data.enterprise) {
            throw "Enterprise '$Slug' not found or token has no access (needs read:enterprise)."
        }
        $enterpriseInfo = $data.enterprise
        $data.enterprise.organizations.nodes | ForEach-Object { $orgs.Add($_) }
        $cursor = $data.enterprise.organizations.pageInfo.endCursor
    } while ($data.enterprise.organizations.pageInfo.hasNextPage)

    return [pscustomobject]@{
        Name = $enterpriseInfo.name
        Slug = $enterpriseInfo.slug
        CreatedAt = $enterpriseInfo.createdAt
        Organizations = @($orgs | Sort-Object login)
    }
}

function Resolve-SectionData {
    <#
    .SYNOPSIS
        Unwraps an Ok/Status/Data result for the public getters: returns Data, or writes a
        non-terminating error on behalf of the calling cmdlet (so -ErrorAction/-ErrorVariable work).
    #>
    param($Result, [string] $What, [Parameter(Mandatory)] $Cmdlet)
    if ($Result.Ok) {
        return $Result.Data
    }
    $reason = if ($Result.Status -eq -1) {
        'GitHub App not installed on this organization/enterprise'
    } elseif ($Result.Status) {
        "HTTP $($Result.Status)"
    } else {
        'request failed'
    }
    $record = [System.Management.Automation.ErrorRecord]::new(
        [System.InvalidOperationException]::new("$What not available ($reason)."),
        'GHESectionNotAvailable', [System.Management.Automation.ErrorCategory]::PermissionDenied, $What)
    $Cmdlet.WriteError($record)
}

function Get-EnterpriseInfo {
    <#
    .SYNOPSIS
        Name, slug, creation date and organizations of the connected enterprise. Falls back to the
        installable_organizations REST endpoint (built for enterprise-installed Apps) when GraphQL fails.
    #>
    $slug = $script:Connection.Enterprise
    try {
        return Get-EnterpriseOrganizations -Slug $slug
    } catch {
        if ($script:AuthMode -ne 'App') {
            throw
        }
        Write-Verbose "GraphQL organization listing failed ($($_.Exception.Message)); using installable_organizations."
        $orgs = Invoke-GitHubRest "enterprises/$slug/apps/installable_organizations" -Paginate
        if (-not $orgs.Ok) {
            throw "Cannot list organizations for enterprise '$slug' (HTTP $($orgs.Status))."
        }
        return [pscustomobject]@{
            Name = $slug
            Slug = $slug
            CreatedAt = $null
            Organizations = @($orgs.Data | ForEach-Object { [pscustomobject]@{ login = $_.login; name = $_.login } } | Sort-Object login)
        }
    }
}
