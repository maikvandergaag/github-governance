function Get-GHOrganizationWebhook {
    <#
    .SYNOPSIS
        Organization webhooks (URL, events, TLS verification). Webhook secrets are never returned.
    .EXAMPLE
        Get-GHOrganization | Get-GHOrganizationWebhook
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
            $r = Get-OrgSection -Org $org -Name 'webhooks'
            Resolve-SectionData -Result $r -What "webhooks for $org" -Cmdlet $PSCmdlet |
                Add-Member -NotePropertyName organization -NotePropertyValue $org -Force -PassThru
        }
    }
}
