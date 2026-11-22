function Get-GHEnterpriseConfiguration {
    <#
    .SYNOPSIS
        Full enterprise snapshot as used by Export-GHDocumentation and Test-GHCompliance.
        Every section is an object with Ok/Status/Data, so missing permissions are explicit.
    #>
    [CmdletBinding()]
    param()
    Assert-GHConnection
    Write-Verbose 'Collecting enterprise configuration ...'
    $graph = Get-EnterpriseGraph
    $snapshot = [ordered]@{ slug = $script:Connection.Enterprise; graph = $graph }
    foreach ($name in $script:EnterpriseSections.Keys) {
        $snapshot[$name] = Get-EnterpriseSection -Name $name
    }
    $snapshot.rulesetDetails = @(Get-EnterpriseRulesetDetails -Graph $graph)
    [pscustomobject]$snapshot
}
