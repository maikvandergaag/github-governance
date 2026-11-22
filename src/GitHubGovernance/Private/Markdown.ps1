function ConvertTo-MdCell {
    param($Value)
    if ($null -eq $Value) {
        return '-'
    }
    if ($Value -is [bool]) {
        return $(if ($Value) {
                'Yes'
            } else {
                'No'
            })
    }
    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) {
        return '-'
    }
    return $text.Replace('|', '\|').Replace("`r", '').Replace("`n", ' ')
}

function ConvertTo-MdTable {
    <#
    .SYNOPSIS
        Builds a Markdown table. Columns is an ordered hashtable: header => scriptblock (receives $_).
    #>
    param(
        [object[]] $InputObject,
        [Parameter(Mandatory)] [System.Collections.Specialized.OrderedDictionary] $Columns
    )

    if (-not $InputObject -or $InputObject.Count -eq 0) {
        return '_None._'
    }
    # Display only: tolerate properties the API omits (rendered as '-') instead of failing under StrictMode.
    Set-StrictMode -Off

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine('| ' + (($Columns.Keys) -join ' | ') + ' |')
    [void]$sb.AppendLine('|' + ((@($Columns.Keys) | ForEach-Object { ' --- ' }) -join '|') + '|')
    foreach ($item in $InputObject) {
        $cells = foreach ($expr in $Columns.Values) {
            $value = $item | ForEach-Object $expr
            ConvertTo-MdCell $value
        }
        [void]$sb.AppendLine('| ' + ($cells -join ' | ') + ' |')
    }
    return $sb.ToString().TrimEnd()
}

function ConvertTo-MdKeyValue {
    param([Parameter(Mandatory)] [System.Collections.Specialized.OrderedDictionary] $Pairs)
    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine('| Setting | Value |')
    [void]$sb.AppendLine('| --- | --- |')
    foreach ($key in $Pairs.Keys) {
        [void]$sb.AppendLine("| $key | $(ConvertTo-MdCell $Pairs[$key]) |")
    }
    return $sb.ToString().TrimEnd()
}

function Format-RulesetConditions {
    # Renders ruleset conditions (ref_name / repository_name / repository_property / repository_id) as one line.
    param($Conditions)
    if (-not $Conditions) {
        return 'none'
    }
    $parts = foreach ($prop in $Conditions.PSObject.Properties) {
        $c = $prop.Value
        $detail = foreach ($key in 'include', 'exclude', 'repository_ids') {
            if ($c -and $c.PSObject.Properties[$key]) {
                $values = @($c.$key | ForEach-Object {
                        if ($_ -is [string] -or $_ -is [ValueType]) {
                            "$_"
                        } else {
                            "$($_.name)=$(@($_.property_values) -join '/')"
                        }  # repository_property entries
                    })
                if ($values.Count -gt 0) {
                    "$key ``$($values -join ', ')``"
                }
            }
        }
        "**$($prop.Name)**: " + $(if ($detail) {
                $detail -join ', '
            } else {
                'any'
            })
    }
    return ($parts -join '; ')
}

function Add-RulesetDetails {
    # Appends a "### Ruleset: <name>" block per ruleset (REST ruleset format, org or enterprise level).
    param(
        # A List[string]; untyped on purpose so PowerShell doesn't convert/enumerate it during binding.
        $Markdown,
        [object[]] $Rulesets
    )
    foreach ($rs in @($Rulesets | Where-Object { $_ } | Sort-Object name)) {
        $Markdown.Add('')
        $Markdown.Add("### Ruleset: $($rs.name)")
        $Markdown.Add('')
        $Markdown.Add("- Target: ``$(Get-Prop $rs 'target')``, enforcement: ``$(Get-Prop $rs 'enforcement')``")
        $Markdown.Add("- Conditions: $(Format-RulesetConditions (Get-Prop $rs 'conditions'))")
        $bypass = @(Get-Prop $rs 'bypass_actors')
        if ($bypass.Count -gt 0 -and $null -ne $bypass[0]) {
            $Markdown.Add('- Bypass actors: ' + (($bypass | ForEach-Object {
                            "$($_.actor_type)$(if ($_.actor_id) { " #$($_.actor_id)" }) ($($_.bypass_mode))"
                        }) -join '; '))
        } else {
            $Markdown.Add('- Bypass actors: none')
        }
        $rules = @(Get-Prop $rs 'rules')
        if ($rules.Count -gt 0 -and $null -ne $rules[0]) {
            $Markdown.Add('- Rules:')
            foreach ($rule in $rules) {
                $paramsJson = if ($rule.PSObject.Properties['parameters'] -and $rule.parameters) {
                    ': `' + ($rule.parameters | ConvertTo-Json -Depth 10 -Compress) + '`'
                }
                $Markdown.Add("  - ``$($rule.type)``$paramsJson")
            }
        } else {
            $Markdown.Add('- Rules: _not returned (check token scopes)_')
        }
    }
}

function New-DocPage {
    <#
    .SYNOPSIS
        Starts a Markdown page (List[string]) with a title and a navigation line.
    #>
    param([string] $Title, [string] $Nav)
    $page = [System.Collections.Generic.List[string]]::new()
    $page.Add("# $Title")
    $page.Add('')
    if ($Nav) {
        $page.Add($Nav); $page.Add('')
    }
    return , $page
}

function New-NavLine {
    # Builds "[A](a.md) · **B** · [C](c.md)" with the current page in bold; $Extra is prepended (e.g. a back link).
    param([System.Collections.Specialized.OrderedDictionary] $Pages, [string] $Current, [string] $Extra)
    $links = foreach ($file in $Pages.Keys) {
        if ($file -eq $Current) {
            "**$($Pages[$file])**"
        } else {
            "[$($Pages[$file])]($file)"
        }
    }
    return (@($Extra) + @($links) | Where-Object { $_ }) -join ' · '
}

function Complete-DocPages {
    # Adds the footer to every page and returns an ordered dictionary file name -> content.
    param([System.Collections.Specialized.OrderedDictionary] $Pages)
    $result = [ordered]@{}
    foreach ($file in $Pages.Keys) {
        $page = $Pages[$file]
        $page.Add('')
        $page.Add('---')
        $page.Add('_Generated by Export-GitHubEnterpriseDocs.ps1. Do not edit manually; changes are overwritten on the next run._')
        $result[$file] = ($page -join "`n") + "`n"
    }
    return $result
}

function Format-Unavailable {
    param($Result)
    if ($Result.Status -eq -1) {
        return '_Not available: the GitHub App is not installed on this organization/enterprise._'
    }
    $code = if ($Result.Status) {
        "HTTP $($Result.Status)"
    } else {
        'request failed'
    }
    return "_Not available ($code). Check token scopes or whether the feature is enabled._"
}

function Format-PolicyValue {
    # Makes enterprise policy enum values readable; NO_POLICY means organizations decide themselves.
    param($Value)
    if ($null -eq $Value) {
        return $null
    }
    if ($Value -is [bool]) {
        return $Value
    }
    switch ([string]$Value) {
        'NO_POLICY' {
            return 'No policy (organizations decide)'
        }
        default {
            return ([string]$Value).ToLowerInvariant().Replace('_', ' ')
        }
    }
}
