function Get-GHConnection {
    <#
    .SYNOPSIS
        Returns the current connection (enterprise, API URL, auth mode and, in App mode, which
        installations have been resolved). Never returns secrets.
    #>
    [CmdletBinding()]
    param()
    Assert-GHConnection
    $installations = if ($script:AuthMode -eq 'App') {
        @($script:TokenCache.Keys | Sort-Object | ForEach-Object {
                [pscustomobject]@{ Scope = $_; Installed = $null -ne $script:TokenCache[$_].Token; TokenExpiresAt = $script:TokenCache[$_].ExpiresAt }
            })
    }
    $script:Connection | Select-Object *, @{ n = 'Installations'; e = { $installations } }
}
