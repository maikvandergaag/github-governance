function Get-GHOrganizationActionsSetting {
    <#
    .SYNOPSIS
        GitHub Actions settings of an organization: permissions, runner groups, self-hosted runners
        and the names (never values) of organization secrets and variables.
        Parts that are not readable are $null (with a warning).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('login')]
        [string[]] $Organization
    )
    begin {
        Assert-GHConnection
    }
    process {
        foreach ($org in $Organization) {
            $out = [ordered]@{ Organization = $org }
            $map = [ordered]@{ Permissions = 'actionsPermissions'; RunnerGroups = 'runnerGroups'; Runners = 'runners'; Secrets = 'actionsSecrets'; Variables = 'actionsVariables' }
            foreach ($key in $map.Keys) {
                $r = Get-OrgSection -Org $org -Name $map[$key]
                $out[$key] = if ($r.Ok) {
                    $r.Data
                } else {
                    Write-Warning "$($map[$key]) for $org not available (HTTP $($r.Status))."; $null
                }
            }
            [pscustomobject]$out
        }
    }
}
