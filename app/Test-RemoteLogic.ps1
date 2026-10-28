#requires -Version 5.1
<#
.SYNOPSIS
    Tests the remote assessment decision path with synthetic SCCM responses.
.DESCRIPTION
    Replaces the registry reader and remote CIM/service commands in an isolated
    script scope. Never contacts a machine or invokes a real scan method.
#>
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$testRoot = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$helpers = [IO.File]::ReadAllText((Join-Path $testRoot 'Validation.Core.ps1'))
. ([scriptblock]::Create($helpers))
$remote = [IO.File]::ReadAllText((Join-Path $testRoot 'Remote.Assessment.ps1'))
$tokens = $null; $errors = $null
$ast = [Management.Automation.Language.Parser]::ParseInput($remote,[ref]$tokens,[ref]$errors)
if ($errors.Count) { throw ($errors | Out-String) }
$definition = $ast.Find({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Get-RegistryRebootReasons' },$false)
$registrySource = $definition.Extent.Text.Replace('[Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, [Microsoft.Win32.RegistryView]::Registry64)','$script:registryDouble')
$remote = $remote.Remove($definition.Extent.StartOffset,$definition.Extent.EndOffset-$definition.Extent.StartOffset).Insert($definition.Extent.StartOffset,'function Get-RegistryRebootReasons { $script:testRebootReasons }')
$remoteBlock = [scriptblock]::Create($remote)
$script:boot = [datetime]::UtcNow.AddHours(-2)
$script:scanTime = [datetime]::UtcNow.AddMinutes(-10)
$script:testRebootReasons = @()
$script:deployedRows = @(); $script:failSdk = $false
$script:storeReads = 0; $script:triggerShape = 'Normal'
$script:clientState = 'Running'; $script:installing = $false; $script:triggers = 0; $script:triggerCode = 0
$script:changeHistory = $false; $script:historyReads = 0
function Get-Service {
    [CmdletBinding()]param($Name)
    [pscustomobject]@{ Status = $script:clientState }
}
function Get-CimInstance {
    param($Namespace,$ClassName,$OperationTimeoutSec)
    switch ($ClassName) {
        'Win32_OperatingSystem' { [pscustomobject]@{ LastBootUpTime = $script:boot } }
        'CCM_SoftwareUpdate' {
            if ($script:failSdk) { throw 'Simulated deployed-update query failure' }
            if ($script:installing) { New-TestDeployedUpdate -Evaluation 7 }
            else { $script:deployedRows }
        }
        'CCM_UpdateStatus' {
            $script:storeReads++
            throw 'Out-of-scope update-store query must not be executed.'
        }
        'CCM_UpdateSource' { [pscustomobject]@{ UniqueId = 'SOURCE-A'; ContentVersion = 7 } }
        'CCM_ScanUpdateSourceHistory' {
            $script:historyReads++
            [pscustomobject]@{ UpdateSourceID = 'SOURCE-A'; UpdateSourceVersion = 7; Valid = $true; LastCompletionTime = $script:scanTime.AddSeconds($(if ($script:changeHistory) { $script:historyReads } else { 0 })) }
        }
        default { throw "Unexpected test class $ClassName" }
    }
}
function New-TestDeployedUpdate {
    param([int]$Compliance = 0,[int]$Evaluation = 0,[bool]$Visible = $true,[string]$Name = '2026-10 Cumulative Update for Windows Server 2016 (KB456)')
    [pscustomobject]@{ ComplianceState = $Compliance; EvaluationState = $Evaluation; ArticleID = '456'; Name = $Name; UpdateID = 'DEPLOYED-A'; UserUIExperience = $Visible; ErrorCode = 0 }
}
function Invoke-CimMethod {
    param($Namespace,$ClassName,$MethodName,$Arguments,$OperationTimeoutSec)
    if ($MethodName -eq 'DetermineIfRebootPending') { return [pscustomobject]@{ ReturnValue = 0; RebootPending = $false; IsHardRebootPending = $false } }
    if ($ClassName -ne 'SMS_Client' -or $MethodName -ne 'TriggerSchedule' -or $Arguments.sScheduleID -ne '{00000000-0000-0000-0000-000000000113}') { throw 'Unapproved remote method in test.' }
    $script:triggers++
    switch ($script:triggerShape) {
        'Empty' { return }
        'Missing' { return [pscustomobject]@{} }
        'Null' { return [pscustomobject]@{ ReturnValue = $null } }
        'Malformed' { return [pscustomobject]@{ ReturnValue = 'invalid' } }
        'Exception' { throw 'Simulated scan submission exception' }
    }
    [pscustomobject]@{ ReturnValue = $script:triggerCode }
}
$script:checks = 0
function Assert-Equal {
    param($Actual,$Expected,$Message)
    if ($Actual -ne $Expected) { throw "$Message : expected '$Expected'; actual '$Actual'." }
    $script:checks++; Write-Output "PASS: $Message"
}
$options = @{ MinimumUptimeSeconds = 120 }
$r = & $remoteBlock (New-ValidationRow 'SERVER01') $helpers $options
Assert-Equal $r.Status 'VERIFICATION PENDING' 'Clear first observation requests verification'
Assert-Equal $r.MissingCount 0 'Empty ClientSDK result has zero visible updates waiting'
Assert-Equal $script:storeReads 0 'Broader update store is not queried'
Assert-Equal ($r.PSObject.Properties.Name -contains 'UpdateStoreMissingCount') $false 'Broader findings are not reported'
Assert-Equal $script:triggers 1 'Exactly one supported scan request submitted'
$again = & $remoteBlock $r $helpers $options
Assert-Equal $again.Status 'VERIFICATION PENDING' 'Old scan cannot confirm new request'
Assert-Equal $script:triggers 1 'Pending verification does not resubmit scans'
$r.ScanRequestedAtUtc = [datetime]::UtcNow.AddMinutes(-2).ToString('o')
$script:scanTime = [datetime]::UtcNow.AddMinutes(-1)
$confirmed = & $remoteBlock $r $helpers $options
Assert-Equal $confirmed.Status 'PASS' 'New valid evidence confirms clear assessment'
Assert-Equal $confirmed.UpdateScope 'Software Center-visible Windows OS and .NET patches' 'Result scope names Software Center visibility'

# Context changes must explain pending verification, not replace the request and
# submit another scan. Capture exact inputs for diagnosis of live pilot mismatches.
$changedBoot = ConvertTo-ValidationRow $r
$changedBoot.ScanRequestBootUtc = $script:boot.AddDays(-1).ToUniversalTime().ToString('o')
$countBeforeContextCheck = $script:triggers
$contextResult = & $remoteBlock $changedBoot $helpers $options
Assert-Equal $contextResult.Status 'VERIFICATION PENDING' 'Boot mismatch keeps verification pending'
Assert-Equal $contextResult.Verification 'BOOT CHANGED' 'Boot mismatch reason is preserved'
Assert-Equal $contextResult.ScanRequestedAtUtc $changedBoot.ScanRequestedAtUtc 'Boot mismatch does not reset request timestamp'
Assert-Equal $script:triggers $countBeforeContextCheck 'Boot mismatch does not submit another scan'
$context = $contextResult.VerificationContextJson | ConvertFrom-Json
Assert-Equal $context.LoadedRequestUtc $changedBoot.ScanRequestedAtUtc 'Diagnostic context records the loaded request'
Assert-Equal $context.SavedRequestBootUtc $changedBoot.ScanRequestBootUtc 'Diagnostic context records exact saved boot'
Assert-Equal $context.ObservedBootUtc $contextResult.LastBootUtc 'Diagnostic context records exact observed boot'
$changedSource = ConvertTo-ValidationRow $r
$parsedSources = ConvertFrom-Json -InputObject $changedSource.ScanBaselineJson
$oldSources = @($parsedSources)
$oldSources[0].Version = '6'
$changedSource.ScanBaselineJson = ConvertTo-Json -InputObject $oldSources -Compress
$contextResult = & $remoteBlock $changedSource $helpers $options
Assert-Equal $contextResult.Verification 'SOURCE CHANGED' 'Source mismatch reason is preserved'
Assert-Equal $contextResult.ScanRequestedAtUtc $changedSource.ScanRequestedAtUtc 'Source mismatch does not reset request timestamp'
Assert-Equal $script:triggers $countBeforeContextCheck 'Source mismatch does not submit another scan'
$context = $contextResult.VerificationContextJson | ConvertFrom-Json
Assert-Equal $context.ObservedSources[0].Version '7' 'Diagnostic context records observed source version'

$script:deployedRows = @(New-TestDeployedUpdate)
$bad = & $remoteBlock $r $helpers $options
Assert-Equal $bad.Status 'ACTION REQUIRED' 'Visible outstanding update blocks PASS'
Assert-Equal $bad.MissingCount 1 'Main missing count uses ClientSDK rather than broader store'
Assert-Equal ($bad.MissingUpdates -like '*DEPLOYED-A*') $true 'Action detail identifies deployed update'
Assert-Equal $bad.ScanRequestedAtUtc '' 'Adverse finding invalidates verification request'
$script:deployedRows = @(New-TestDeployedUpdate -Visible $false)
$bad = & $remoteBlock $r $helpers $options
Assert-Equal $bad.Status 'PASS' 'Hidden outstanding deployment is outside the agreed scope'
Assert-Equal $bad.MissingCount 0 'Hidden deployment does not contribute to visible waiting count'
$script:deployedRows = @(New-TestDeployedUpdate -Visible $false -Evaluation 7)
$bad = & $remoteBlock $r $helpers $options
Assert-Equal $bad.Status 'PASS' 'Hidden installation does not block visible-update assessment'
$script:deployedRows = @(New-TestDeployedUpdate -Evaluation 8)
$bad = & $remoteBlock $r $helpers $options
Assert-Equal $bad.RebootPending 'Yes' 'ClientSDK pending-reboot state blocks clear result'
$script:deployedRows = @(); $script:testRebootReasons = @('Windows servicing')
$bad = & $remoteBlock $r $helpers $options
Assert-Equal $bad.Status 'ACTION REQUIRED' 'Windows servicing reboot blocks PASS'
$script:testRebootReasons = @(); $script:clientState = 'Stopped'
$bad = & $remoteBlock $r $helpers $options
Assert-Equal $bad.Status 'NOT READY' 'Stopped SCCM client is explained'
$script:clientState = 'Running'; $script:installing = $true
$bad = & $remoteBlock $r $helpers $options
Assert-Equal $bad.Status 'NOT READY' 'Active update installation blocks assessment'
$script:installing = $false; $script:deployedRows = @(New-TestDeployedUpdate -Compliance 2)
$bad = & $remoteBlock $r $helpers $options
Assert-Equal $bad.Status 'UNABLE TO DETERMINE' 'Indeterminate deployed compliance cannot appear clean'
$script:deployedRows = @(New-TestDeployedUpdate -Visible $false -Compliance 2)
$bad = & $remoteBlock $r $helpers $options
Assert-Equal $bad.Status 'PASS' 'Hidden indeterminate compliance is outside the agreed scope'
$script:deployedRows = @()
$script:failSdk = $true
$bad = & $remoteBlock $r $helpers $options
Assert-Equal $bad.Status 'UNABLE TO DETERMINE' 'ClientSDK failure is not treated as zero deployments'
$script:failSdk = $false; $script:changeHistory = $true
$bad = & $remoteBlock $r $helpers $options
Assert-Equal $bad.Status 'NOT READY' 'Changing history rejects inconsistent snapshot'
$script:changeHistory = $false; $script:triggerCode = 5
$bad = & $remoteBlock (New-ValidationRow 'SERVER01') $helpers $options
Assert-Equal $bad.Status 'UNABLE TO DETERMINE' 'Scan request error is surfaced'
Assert-Equal ([bool]$bad.ScanRequestedAtUtc) $true 'Uncertain submission boundary is preserved'
Assert-Equal $bad.ScanRequestOutcome 'Rejected' 'Explicit provider failure remains rejected'
Assert-Equal ([bool]$bad.Diagnostics) $true 'Error diagnostics are explicitly populated'
$script:triggerCode = 0
foreach ($shape in @('Empty','Missing','Null','Malformed')) {
    $script:triggerShape = $shape
    $script:scanTime = [datetime]::UtcNow.AddMinutes(-10)
    $pending = & $remoteBlock (New-ValidationRow 'SERVER01') $helpers $options
    Assert-Equal $pending.Status 'VERIFICATION PENDING' "$shape response waits for evidence instead of failing property lookup"
    Assert-Equal $pending.Verification 'REQUEST UNCONFIRMED' "$shape response is not reported as accepted"
    Assert-Equal ([bool]$pending.ScanRequestDetails) $true "$shape response preserves diagnostic shape"
    $count = $script:triggers
    $pendingAgain = & $remoteBlock $pending $helpers $options
    Assert-Equal $script:triggers $count "$shape response does not cause duplicate scan requests"
    Assert-Equal $pendingAgain.Status 'VERIFICATION PENDING' "$shape response cannot PASS without new completion evidence"
    $pending.ScanRequestedAtUtc = [datetime]::UtcNow.AddMinutes(-2).ToString('o')
    $script:scanTime = [datetime]::UtcNow.AddMinutes(-1)
    $verified = & $remoteBlock $pending $helpers $options
    Assert-Equal $verified.Status 'PASS' "$shape response can PASS only after qualifying scan evidence"
}
$script:triggerShape = 'Exception'
$bad = & $remoteBlock (New-ValidationRow 'SERVER01') $helpers $options
Assert-Equal $bad.Status 'UNABLE TO DETERMINE' 'Thrown submission error remains a failure'
Assert-Equal $bad.ScanRequestOutcome 'Unconfirmed' 'Submission exception preserves uncertainty'
Assert-Equal ($bad.Diagnostics -like '*Submitting SCCM verification scan*') $true 'Submission diagnostics identify the failing stage'
$script:triggerShape = 'Normal'
$interrupted = New-ValidationRow 'SERVER01'; $interrupted.Verification = 'ATTEMPT IN PROGRESS'
$beforeCount = $script:triggers
$bad = & $remoteBlock $interrupted $helpers $options
Assert-Equal $bad.Status 'UNABLE TO DETERMINE' 'Interrupted dispatch does not silently restart workflow'
Assert-Equal $script:triggers $beforeCount 'Interrupted state cannot trigger another scan'
Assert-Equal $script:storeReads 0 'No decision path reads the broader update store'

# Strict reboot checks must never query PFRO, even indirectly through the generic
# SCCM aggregate method. Exercise the actual registry function with a fake base key.
$script:registryMode = 'PFRO-only'; $script:openedKeys = New-Object System.Collections.ArrayList
$script:registryDisposed = $false
$script:registryDouble = [pscustomobject]@{}
$script:registryDouble | Add-Member ScriptMethod OpenSubKey {
    param($Path)
    [void]$script:openedKeys.Add($Path)
    if ($Path -like '*Session Manager*') { throw 'PFRO key must not be opened.' }
    if (($script:registryMode -eq 'CBS' -and $Path -like '*Component Based Servicing*') -or ($script:registryMode -eq 'WU' -and $Path -like '*WindowsUpdate*')) {
        $key = [pscustomobject]@{}; $key | Add-Member ScriptMethod Dispose {}; return $key
    }
    return $null
}
$script:registryDouble | Add-Member ScriptMethod Dispose { $script:registryDisposed = $true }
$registryBlock = [scriptblock]::Create($registrySource + '; Get-RegistryRebootReasons')
Assert-Equal @(& $registryBlock).Count 0 'PFRO-only state yields no patch/OS reboot reason'
Assert-Equal $script:openedKeys.Count 2 'Strict reader opens only CBS and Windows Update keys'
Assert-Equal $script:registryDisposed $true 'Strict registry reader disposes its base key'
$script:registryMode = 'CBS'
Assert-Equal (@(& $registryBlock) -join ',') 'Windows servicing' 'CBS reboot remains authoritative'
$script:registryMode = 'WU'
Assert-Equal (@(& $registryBlock) -join ',') 'Windows Update' 'Windows Update reboot remains authoritative'

$script:deployedRows = @(New-TestDeployedUpdate -Name 'Security Update for Microsoft Office 2016 (KB456)' -Evaluation 13)
$scopeResult = & $remoteBlock $r $helpers $options
Assert-Equal $scopeResult.Status 'PASS' 'Excluded product failure does not block OS-only verification'
Assert-Equal $scopeResult.ScopeExcludedCount 1 'Excluded visible updates are counted separately'
Assert-Equal $scopeResult.FailedUpdateCount 0 'Excluded product failure is not labeled an OS/.NET failure'
$script:deployedRows = @(New-TestDeployedUpdate -Name '2026-10 Cumulative Update for .NET Framework 4.8 for Windows Server 2016 (KB456)' -Evaluation 13)
$scopeResult = & $remoteBlock $r $helpers $options
Assert-Equal $scopeResult.Status 'ACTION REQUIRED' '.NET failure is in patch scope'
Assert-Equal $scopeResult.VisibleUpdatesFailed 'Yes' 'EvaluationState 13 records visible scoped failure'
Assert-Equal ($scopeResult.FailedUpdates -like '*Evaluation=13*') $true 'Failure details include the actual client evaluation state'
$script:clientState = 'Stopped'
$scopeResult = & $remoteBlock $r $helpers $options
Assert-Equal $scopeResult.Status 'NOT READY' 'Stopped client remains not ready even with a known failed patch'
Assert-Equal ($scopeResult.Reason -like '*failures: Yes*') $true 'NOT READY reason identifies reported failed OS/.NET updates'
$script:failSdk = $true
$scopeResult = & $remoteBlock $r $helpers $options
Assert-Equal $scopeResult.Status 'NOT READY' 'Unavailable update data does not erase a known readiness issue'
Assert-Equal $scopeResult.VisibleUpdatesFailed 'Unknown' 'Failed query is never mislabeled as no visible failures'
$script:failSdk = $false; $script:clientState = 'Running'
$script:deployedRows = @(New-TestDeployedUpdate -Evaluation 7)
$scopeResult = & $remoteBlock $r $helpers $options
Assert-Equal $scopeResult.VisibleUpdatesFailed 'No' 'An installing patch is not mislabeled as failed'
Assert-Equal ($scopeResult.Reason -like '*failures: No*') $true 'NOT READY explicitly notes no reported scoped failures'
$script:deployedRows = @((New-TestDeployedUpdate -Evaluation 7),(New-TestDeployedUpdate -Evaluation 13))
$scopeResult = & $remoteBlock $r $helpers $options
Assert-Equal $scopeResult.Status 'NOT READY' 'Concurrent installation keeps mixed-error state not ready'
Assert-Equal $scopeResult.VisibleUpdatesFailed 'Yes' 'NOT READY detects another visible scoped update failure'
$script:deployedRows = @(New-TestDeployedUpdate -Name 'Vendor maintenance package')
$scopeResult = & $remoteBlock $r $helpers $options
Assert-Equal $scopeResult.Status 'NOT READY' 'Ambiguous scope cannot silently authorize PASS'
Assert-Equal $scopeResult.ScopeAmbiguousCount 1 'Scope review identifies the ambiguous visible update'
$script:deployedRows = @()
$script:genericCalls = 0
function Invoke-CimMethod {
    param($Namespace,$ClassName,$MethodName,$Arguments,$OperationTimeoutSec)
    if ($ClassName -eq 'CCM_ClientUtilities') { $script:genericCalls++; return [pscustomobject]@{ReturnValue=0;RebootPending=$true;IsHardRebootPending=$true} }
    throw 'A saved verification must not submit another scan.'
}
$scopeResult = & $remoteBlock $r $helpers $options
Assert-Equal $scopeResult.Status 'PASS' 'No generic reboot flag blocks a clean OS-only verification'
Assert-Equal $script:genericCalls 0 'Generic SCCM reboot method is not called in strict mode'
Write-Output "Remote logic checks passed: $script:checks"
