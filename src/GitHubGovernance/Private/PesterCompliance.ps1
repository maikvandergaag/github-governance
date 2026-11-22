function Invoke-GHPesterChecks {
    param(
        [System.Collections.IDictionary] $Checks,
        [string] $TargetId,
        [string] $Organization,
        [string] $Repository,
        $Policy,
        [string] $TestsPath,
        [switch] $SkipCodeOwners
    )

    $exemptProp = if ($Policy.PSObject.Properties['exemptions']) {
        $Policy.exemptions.PSObject.Properties[$TargetId]
    }
    $exempt = if ($exemptProp) {
        @($exemptProp.Value)
    } else {
        @()
    }
    $failures = [System.Collections.Generic.List[object]]::new()
    $notEvaluated = [System.Collections.Generic.List[object]]::new()
    $selected = [System.Collections.Generic.List[object]]::new()

    foreach ($id in $Checks.Keys) {
        $configProp = $Policy.checks.PSObject.Properties[$id]
        if (-not $configProp -or -not $configProp.Value.enabled -or $id -in $exempt) {
            continue
        }
        if ($SkipCodeOwners -and (Get-Prop $Checks[$id].DataSource 'codeOwners')) {
            $notEvaluated.Add([ordered]@{ check = $id; reason = 'CODEOWNERS checks were skipped by -SkipCodeOwners.' })
            continue
        }
        $selected.Add(@{ Id = $id; Path = $Checks[$id].Path; Config = $configProp.Value })
    }

    if ($selected.Count -gt 0) {
        $containers = foreach ($check in $selected) {
            # Nested Pester scopes hide module state, so evaluate before entering Pester.
            $result = Invoke-GHComplianceCheck -CheckId $check.Id -Organization $Organization -Repository $Repository `
                -Config $check.Config -TestsPath $TestsPath
            $context = @{
                Id = $check.Id; Config = $check.Config
                Organization = $Organization; Repository = $Repository; Result = $result
            }
            New-PesterContainer -Path $check.Path -Data @{ ComplianceContext = $context }
        }
        $config = New-PesterConfiguration
        $config.Run.Container = @($containers)
        $config.Run.PassThru = $true
        $config.Output.Verbosity = 'None'
        $lastExitCode = Get-Variable LASTEXITCODE -Scope Global -ErrorAction Ignore
        $previousExitCode = if ($null -ne $lastExitCode) {
            $lastExitCode.Value
        } else {
            $null
        }
        try {
            $run = Invoke-Pester -Configuration $config
        } finally {
            # Findings are handled below; Pester's failure exit code must not leak into the caller.
            if ($null -ne $lastExitCode) {
                $global:LASTEXITCODE = $previousExitCode
            } else {
                Remove-Variable LASTEXITCODE -Scope Global -ErrorAction Ignore
            }
        }
        if (@($run.Containers).Count -ne $selected.Count) {
            throw "Pester did not execute all checks for $TargetId."
        }

        foreach ($container in $run.Containers) {
            $context = $container.Data.ComplianceContext
            $id = $context.Id
            $tests = @($container.Blocks | ForEach-Object { $_.Tests })
            $result = $context.Result
            if ($container.ErrorRecord.Count -gt 0 -or $tests.Count -ne 1 -or $null -eq $result) {
                $errors = @($container.ErrorRecord) + @($container.Blocks | ForEach-Object { $_.ErrorRecord }) +
                @($tests | ForEach-Object { $_.ErrorRecord })
                $details = @($errors | ForEach-Object { "$_ $($_.ScriptStackTrace)" }) -join '; '
                throw "Pester could not evaluate $id for ${TargetId}: $details"
            }
            $status = switch ($result.status) {
                'pass' {
                    'Passed'
                }
                'fail' {
                    'Failed'
                }
                { $_ -in 'na', 'notEvaluated' } {
                    'Skipped'
                }
                default {
                    throw "Pester returned an invalid status for $id on ${TargetId}: $($result.status)"
                }
            }
            if ($tests[0].Result -ne $status) {
                throw "Pester result for $id on $TargetId was $($tests[0].Result), expected $status. $($tests[0].ErrorRecord -join '; ')"
            }
            if ($status -eq 'Failed') {
                if ($tests[0].ErrorRecord.Count -ne 1 -or $tests[0].ErrorRecord[0].FullyQualifiedErrorId -ne 'PesterAssertionFailed') {
                    throw "Pester encountered an unexpected error for $id on ${TargetId}: $($tests[0].ErrorRecord -join '; ')"
                }
                $failures.Add([ordered]@{
                        check = $id; severity = (Get-Prop $context.Config 'severity') ?? 'medium'
                        title = $Checks[$id].Title; detail = $result.detail; remediation = $Checks[$id].Remediation
                        policyParameters = (Get-Prop $context.Config 'params')
                    })
            } elseif ($status -eq 'Skipped') {
                $notEvaluated.Add([ordered]@{ check = $id; reason = $result.detail })
            }
        }
    }
    return @{ failures = $failures.ToArray(); notEvaluated = $notEvaluated.ToArray() }
}
