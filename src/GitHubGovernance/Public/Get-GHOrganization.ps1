function Get-GHOrganization {
    <#
    .SYNOPSIS
        Lists the connected standalone organization or organizations of the connected enterprise.
    .EXAMPLE
        Get-GHOrganization | Get-GHOrganizationSetting
    #>
    [CmdletBinding()]
    param()
    Assert-GHConnection
    if ($script:Connection.Scope -eq 'organization') {
        $result = Invoke-GitHubRest "orgs/$($script:Connection.Account)"
        Resolve-SectionData -Result $result -What "organization $($script:Connection.Account)" -Cmdlet $PSCmdlet
    } elseif ($script:Connection.Scope -eq 'user') {
        throw 'A personal account connection does not have an organization inventory.'
    } else {
        (Get-EnterpriseInfo).Organizations
    }
}
