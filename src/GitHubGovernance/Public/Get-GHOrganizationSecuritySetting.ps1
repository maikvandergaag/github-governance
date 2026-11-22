function Get-GHOrganizationSecuritySetting {
    <#
    .SYNOPSIS
        Security and governance settings of an organization: code security configurations,
        custom properties and custom repository roles. Parts that are not readable are $null (with a warning).
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
            $map = [ordered]@{ CodeSecurityConfigurations = 'securityConfigs'; CustomProperties = 'customProperties'; CustomRepositoryRoles = 'customRepoRoles' }
            foreach ($key in $map.Keys) {
                $r = Get-OrgSection -Org $org -Name $map[$key]
                $out[$key] = if ($r.Ok) {
                    $r.Data
                } else {
                    Write-Warning "$($map[$key]) for $org not available (HTTP $($r.Status))."; $null
                }
            }
            if ($out.CustomRepositoryRoles) {
                $out.CustomRepositoryRoles = @(Get-Prop $out.CustomRepositoryRoles 'custom_roles')
            }
            [pscustomobject]$out
        }
    }
}
