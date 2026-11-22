#
# Module manifest for module 'GitHubGovernance'
#
# Generated on: 11/20/2026
#

@{

    # Script module or binary module file associated with this manifest.
    RootModule = 'GitHubGovernance.psm1'

    # Version number of this module.
    ModuleVersion = '1.0.0'

    # Supported PSEditions
    CompatiblePSEditions = 'Core'

    # ID used to uniquely identify this module
    GUID = 'e872ba45-4eeb-4359-b5d0-1e5474afbad8'

    # Description of the functionality provided by this module
    Description = 'Documents a GitHub Enterprise Cloud environment (enterprise, organizations, repositories, CODEOWNERS) and evaluates it against a compliance policy (issues + code scanning).'

    # Minimum version of the PowerShell engine required by this module
    PowerShellVersion = '7.2'

    # Name of the PowerShell host required by this module
    # PowerShellHostName = ''

    # Minimum version of the PowerShell host required by this module
    # PowerShellHostVersion = ''

    # Minimum version of Microsoft .NET Framework required by this module. This prerequisite is valid for the PowerShell Desktop edition only.
    # DotNetFrameworkVersion = ''

    # Minimum version of the common language runtime (CLR) required by this module. This prerequisite is valid for the PowerShell Desktop edition only.
    # ClrVersion = ''

    # Processor architecture (None, X86, Amd64) required by this module
    # ProcessorArchitecture = ''

    # Modules that must be imported into the global environment prior to importing this module
    # RequiredModules = @()

    # Assemblies that must be loaded prior to importing this module
    # RequiredAssemblies = @()

    # Script files (.ps1) that are run in the caller's environment prior to importing this module.
    # ScriptsToProcess = @()

    # Type files (.ps1xml) to be loaded when importing this module
    # TypesToProcess = @()

    # Format files (.ps1xml) to be loaded when importing this module
    # FormatsToProcess = @()

    # Modules to import as nested modules of the module specified in RootModule/ModuleToProcess
    # NestedModules = @()

    # Functions to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no functions to export.
    FunctionsToExport = 'Connect-GHGovernance', 'ConvertTo-GHComplianceSarif',
    'Disconnect-GHGovernance', 'Export-GHDocumentation',
    'Get-GHCodeOwners', 'Get-GHConnection',
    'Get-GHEnterpriseActionsSetting', 'Get-GHEnterpriseConfiguration',
    'Get-GHEnterprisePolicy', 'Get-GHEnterpriseRuleset',
    'Get-GHEnterpriseSecuritySetting', 'Get-GHOrganization',
    'Get-GHOrganizationActionsSetting', 'Get-GHOrganizationApp',
    'Get-GHOrganizationConfiguration', 'Get-GHOrganizationCopilot',
    'Get-GHOrganizationMember', 'Get-GHOrganizationRuleset',
    'Get-GHOrganizationSecuritySetting', 'Get-GHOrganizationSetting',
    'Get-GHOrganizationTeam', 'Get-GHOrganizationWebhook',
    'Get-GHRepository', 'Invoke-GHComplianceCheck', 'Invoke-GHGraphQL', 'Invoke-GHRestMethod',
    'Sync-GHComplianceIssue', 'Test-GHCompliance'

    # Cmdlets to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no cmdlets to export.
    CmdletsToExport = @()

    # Variables to export from this module
    # VariablesToExport = @()

    # Aliases to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no aliases to export.
    AliasesToExport = @()

    # DSC resources to export from this module
    # DscResourcesToExport = @()

    # List of all modules packaged with this module
    # ModuleList = @()

    # List of all files packaged with this module
    # FileList = @()

    # Private data to pass to the module specified in RootModule/ModuleToProcess. This may also contain a PSData hashtable with additional module metadata used by PowerShell.
    PrivateData = @{

        PSData = @{

            # Tags applied to this module. These help with module discovery in online galleries.
            Tags = 'GitHub', 'Enterprise', 'Governance', 'Compliance', 'Documentation'

            # A URL to the license for this module.
            # LicenseUri = ''

            # A URL to the main website for this project.
            # ProjectUri = ''

            # A URL to an icon representing this module.
            # IconUri = ''

            # ReleaseNotes of this module
            # ReleaseNotes = ''

            # Prerelease string of this module
            # Prerelease = ''

            # Flag to indicate whether the module requires explicit user acceptance for install/update/save
            # RequireLicenseAcceptance = $false

            # External dependent modules of this module
            # ExternalModuleDependencies = @()

        } # End of PSData hashtable

    } # End of PrivateData hashtable

    # HelpInfo URI of this module
    # HelpInfoURI = ''

    # Default prefix for commands exported from this module. Override the default prefix using Import-Module -Prefix.
    # DefaultCommandPrefix = ''

}

