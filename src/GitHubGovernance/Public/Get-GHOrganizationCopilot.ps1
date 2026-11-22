function Get-GHOrganizationCopilot {
    <#
    .SYNOPSIS
        Copilot settings and seat breakdown of the organization.
    .EXAMPLE
        Get-GHOrganization | Get-GHOrganizationCopilot
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
            $r = Get-OrgSection -Org $org -Name 'copilot'
            Resolve-SectionData -Result $r -What "copilot for $org" -Cmdlet $PSCmdlet |
                Add-Member -NotePropertyName organization -NotePropertyValue $org -Force -PassThru
        }
    }
}
