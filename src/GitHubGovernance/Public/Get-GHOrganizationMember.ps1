function Get-GHOrganizationMember {
    <#
    .SYNOPSIS
        Members of an organization. -Role Admin returns owners; -OutsideCollaborators returns
        outside collaborators instead of members.
    .EXAMPLE
        Get-GHOrganization | Get-GHOrganizationMember -Role Admin
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('login')]
        [string[]] $Organization,
        [ValidateSet('All', 'Admin')]
        [string] $Role = 'All',
        [switch] $OutsideCollaborators
    )
    begin {
        Assert-GHConnection
    }
    process {
        foreach ($org in $Organization) {
            $section = if ($OutsideCollaborators) {
                'outsideCollaborators'
            } elseif ($Role -eq 'Admin') {
                'admins'
            } else {
                'members'
            }
            Resolve-SectionData -Result (Get-OrgSection -Org $org -Name $section) -What "$section for $org" -Cmdlet $PSCmdlet |
                Add-Member -NotePropertyName organization -NotePropertyValue $org -Force -PassThru
        }
    }
}
