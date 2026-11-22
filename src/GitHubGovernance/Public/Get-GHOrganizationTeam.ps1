function Get-GHOrganizationTeam {
    <#
    .SYNOPSIS
        Teams of the organization.
    .EXAMPLE
        Get-GHOrganization | Get-GHOrganizationTeam
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
            $r = Get-OrgSection -Org $org -Name 'teams'
            Resolve-SectionData -Result $r -What "teams for $org" -Cmdlet $PSCmdlet |
                Add-Member -NotePropertyName organization -NotePropertyValue $org -Force -PassThru
        }
    }
}
