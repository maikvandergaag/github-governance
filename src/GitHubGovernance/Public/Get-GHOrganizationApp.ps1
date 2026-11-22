function Get-GHOrganizationApp {
    <#
    .SYNOPSIS
        GitHub Apps installed on the organization, with their permissions.
    .EXAMPLE
        Get-GHOrganization | Get-GHOrganizationApp
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
            $r = Get-OrgSection -Org $org -Name 'installations'
            Resolve-SectionData -Result $r -What "installations for $org" -Cmdlet $PSCmdlet |
                Add-Member -NotePropertyName organization -NotePropertyValue $org -Force -PassThru
        }
    }
}
