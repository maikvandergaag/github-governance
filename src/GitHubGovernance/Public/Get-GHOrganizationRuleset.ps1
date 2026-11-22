function Get-GHOrganizationRuleset {
    <#
    .SYNOPSIS
        Organization rulesets including conditions, bypass actors and rules.
    .EXAMPLE
        Get-GHOrganizationRuleset my-org | Where-Object enforcement -eq 'active'
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
            $list = Get-OrgSection -Org $org -Name 'rulesets'
            if (-not $list.Ok) {
                Resolve-SectionData -Result $list -What "rulesets for $org" -Cmdlet $PSCmdlet; continue
            }
            Get-OrgRulesetDetails -Org $org -RulesetsResult $list |
                Add-Member -NotePropertyName organization -NotePropertyValue $org -Force -PassThru
        }
    }
}
