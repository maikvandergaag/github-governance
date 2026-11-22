function Disconnect-GHGovernance {
    <#
    .SYNOPSIS
        Clears the connection and all cached credentials and installation tokens from the session.
    #>
    [CmdletBinding()]
    param()
    $script:Connection = $null
    $script:TokenCache = @{}
    $script:AppClientId = $null
    $script:AppPrivateKey = $null
    $script:PatToken = $null
    $script:AuthMode = $null
}
