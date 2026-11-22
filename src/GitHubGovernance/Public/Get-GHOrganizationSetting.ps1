function Get-GHOrganizationSetting {
    <#
    .SYNOPSIS
        General organization settings (2FA requirement, base permission, repository creation, security defaults for new repositories).
    .EXAMPLE
        Get-GHOrganization | Get-GHOrganizationSetting
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
            $r = Get-OrgSection -Org $org -Name 'settings'
            Resolve-SectionData -Result $r -What "settings for $org" -Cmdlet $PSCmdlet |
                Add-Member -NotePropertyName organization -NotePropertyValue $org -Force -PassThru
        }
    }
}
