function Get-GHEnterpriseSecuritySetting {
    <#
    .SYNOPSIS
        Enterprise code security configurations, custom properties and audit log streams.
        Parts that are not readable are $null (with a warning).
    #>
    [CmdletBinding()]
    param()
    Assert-GHConnection
    $out = [ordered]@{}
    foreach ($name in 'securityConfigs', 'customProperties', 'auditLogStreams') {
        $r = Get-EnterpriseSection -Name $name
        $out[$name] = if ($r.Ok) {
            $r.Data
        } else {
            Write-Warning "Enterprise $name not available (HTTP $($r.Status))."; $null
        }
    }
    [pscustomobject]@{
        CodeSecurityConfigurations = $out.securityConfigs
        CustomProperties = $out.customProperties
        AuditLogStreams = $out.auditLogStreams
    }
}
