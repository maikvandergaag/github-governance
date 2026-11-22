function Get-GHEnterpriseActionsSetting {
    <#
    .SYNOPSIS
        Enterprise GitHub Actions policy, runner groups and self-hosted runners.
        Parts that are not readable are $null (with a warning).
    #>
    [CmdletBinding()]
    param()
    Assert-GHConnection
    $out = [ordered]@{}
    foreach ($name in 'actionsPermissions', 'runnerGroups', 'runners') {
        $r = Get-EnterpriseSection -Name $name
        $out[$name] = if ($r.Ok) {
            $r.Data
        } else {
            Write-Warning "Enterprise $name not available (HTTP $($r.Status))."; $null
        }
    }
    [pscustomobject]@{ Permissions = $out.actionsPermissions; RunnerGroups = $out.runnerGroups; Runners = $out.runners }
}
