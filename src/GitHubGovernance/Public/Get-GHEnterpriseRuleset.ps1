function Get-GHEnterpriseRuleset {
    <#
    .SYNOPSIS
        Enterprise rulesets including conditions, bypass actors and rules.
    #>
    [CmdletBinding()]
    param()
    Assert-GHConnection
    $graph = Get-EnterpriseGraph
    if (-not $graph.Ok) {
        Write-Error 'Enterprise rulesets not available.'; return
    }
    Get-EnterpriseRulesetDetails -Graph $graph
}
