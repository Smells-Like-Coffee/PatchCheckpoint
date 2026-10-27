<#
.SYNOPSIS
    Runs a single assessment on a target Windows computer through WinRM.
.DESCRIPTION
    Reads Software Center-visible SCCM updates, client readiness,
    scan history, and reboot indicators. The sole state-changing action is schedule
    113, requested only when initial checks are clear. No installation or reboot
    methods are called. Uncertain evidence prevents PASS.
#>
param($InputRow, [string]$HelperSource, $Options)
. ([scriptblock]::Create($HelperSource))
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$row = ConvertTo-ValidationRow $InputRow
$row.Status = 'UNABLE TO DETERMINE'; $row.Reason = ''
$row.CheckedAtUtc = [datetime]::UtcNow.ToString('o')
$row.MissingCount = ''; $row.MissingUpdates = ''; $row.RebootPending = 'Unknown'
$row.UpdateScope = 'Software Center-visible SCCM updates'
$row.RebootReasons = ''; $row.Diagnostics = ''; $row.ScanEvidenceJson = ''; $row.Verification = ''
$row.VerificationContextJson = ''
if ($InputRow.Verification -eq 'ATTEMPT IN PROGRESS' -and -not $InputRow.ScanRequestedAtUtc) {
    $row.Reason = 'Prior assessment was interrupted before scan submission could be recorded. Review client logs, then use a names-only input for a new verification request.'
    $row.Verification = 'ATTEMPT IN PROGRESS'
    return $row
}

# Missing properties and unrecognized class layouts fail conservatively. These
# internal client classes must be validated against the estate's SCCM version.
function Get-RequiredProperty {
    param($Object, [string]$Name)
    if ($null -eq $Object -or $Object.PSObject.Properties.Name -notcontains $Name -or $null -eq $Object.$Name) {
        throw "Required SCCM property '$Name' is unavailable."
    }
    $Object.$Name
}
function ConvertTo-UtcText {
    param($Value)
    if (-not $Value) { return '' }
    if ($Value -is [datetime]) { return $Value.ToUniversalTime().ToString('o') }
    [Management.ManagementDateTimeConverter]::ToDateTime([string]$Value).ToUniversalTime().ToString('o')
}

# Read source-specific history on both sides of the deployed-update query. A change
# during collection invalidates the snapshot instead of allowing a stale zero count.
function Get-ScanSnapshot {
    $sources = @(Get-CimInstance -Namespace root\ccm\SoftwareUpdates\WUAHandler -ClassName CCM_UpdateSource -OperationTimeoutSec 20 | ForEach-Object {
        [pscustomobject]@{ Id = [string](Get-RequiredProperty $_ 'UniqueId'); Version = [string](Get-RequiredProperty $_ 'ContentVersion') }
    } | Sort-Object Id)
    if (-not $sources.Count) { throw 'No SCCM update sources were returned.' }
    $history = @(Get-CimInstance -Namespace root\ccm\ScanAgent -ClassName CCM_ScanUpdateSourceHistory -OperationTimeoutSec 20 | ForEach-Object {
        [pscustomobject]@{
            Id = [string](Get-RequiredProperty $_ 'UpdateSourceID')
            Version = [string](Get-RequiredProperty $_ 'UpdateSourceVersion')
            Valid = (Get-RequiredProperty $_ 'Valid') -eq $true
            CompletedUtc = ConvertTo-UtcText (Get-RequiredProperty $_ 'LastCompletionTime')
        }
    } | Sort-Object Id)
    [pscustomobject]@{ Sources = $sources; History = $history; Signature = (ConvertTo-Json -InputObject @($sources,$history) -Depth 6 -Compress) }
}

function Get-RegistryRebootReasons {
    $reasons = New-Object 'System.Collections.Generic.List[string]'
    $registry = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, [Microsoft.Win32.RegistryView]::Registry64)
    try {
        $keys = @{
            'Windows servicing' = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'
            'Windows Update' = 'SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
        }
        foreach ($label in $keys.Keys) {
            $key = $registry.OpenSubKey($keys[$label])
            if ($null -ne $key) { $reasons.Add($label); $key.Dispose() }
        }
        $key = $registry.OpenSubKey('SYSTEM\CurrentControlSet\Control\Session Manager')
        if ($null -eq $key) { throw 'Session Manager registry key is unavailable.' }
        try {
            $renames = @($key.GetValue('PendingFileRenameOperations')) + @($key.GetValue('PendingFileRenameOperations2'))
            if (@($renames | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count) { $reasons.Add('Pending file rename operations') }
        }
        finally { $key.Dispose() }
    }
    finally { $registry.Dispose() }
    $reasons.ToArray()
}
$stage = 'Reading Windows and client readiness'
try {
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -OperationTimeoutSec 20
    $row.LastBootUtc = ConvertTo-UtcText $os.LastBootUpTime
    $row.UptimeMinutes = [math]::Round(([datetime]::UtcNow - ([datetimeoffset]::Parse($row.LastBootUtc).UtcDateTime)).TotalMinutes, 2)
    if ([double]$row.UptimeMinutes -lt 0) { throw 'Server clock is earlier than its boot time.' }
    $row.ClientService = (Get-Service -Name CcmExec -ErrorAction Stop).Status.ToString()
    if ($row.ClientService -ne 'Running') {
        $row.Status = 'NOT READY'; $row.Reason = "SCCM client service is $($row.ClientService)."; return $row
    }
    # A short startup guard is explicit and configurable; process names alone do
    # not establish that Windows servicing is active or finished.
    if ([double]$row.UptimeMinutes -lt ([double]$Options.MinimumUptimeSeconds / 60)) {
        $row.Status = 'NOT READY'; $row.Reason = "Recent boot: uptime is $($row.UptimeMinutes) minutes; startup guard has not elapsed."; return $row
    }

    $before = $null; $scanError = ''
    try { $before = Get-ScanSnapshot } catch { $scanError = $_.Exception.Message }
    # Use Software Center's backing API, filtered by its documented visibility flag.
    # Hidden deployments and broader update-store findings are outside this scope.
    $stage = 'Reading Software Center-visible updates'
    $allDeployed = @(Get-CimInstance -Namespace root\ccm\ClientSDK -ClassName CCM_SoftwareUpdate -OperationTimeoutSec 20)
    $deployed = @($allDeployed | Where-Object { (Get-RequiredProperty $_ 'UserUIExperience') -eq $true })
    $missing = @($deployed | Where-Object { (Get-RequiredProperty $_ 'ComplianceState') -eq 0 })
    $unknown = @($deployed | Where-Object { $_.ComplianceState -notin @(0,1) })
    $row.MissingCount = $missing.Count
    $row.MissingUpdates = ($missing | ForEach-Object {
        'Article={0}; Title={1}; ID={2}; Evaluation={3}; VisibleInSoftwareCenter={4}' -f $_.ArticleID, $_.Name, $_.UpdateID, $_.EvaluationState, $_.UserUIExperience
    }) -join ' | '
    if (@($deployed | Where-Object { (Get-RequiredProperty $_ 'EvaluationState') -in @(7,11) }).Count) {
        Clear-VerificationRequest $row
        $row.Status = 'NOT READY'; $row.Reason = 'A Software Center-visible update is installing or verifying installation.'; return $row
    }

    $reasons = New-Object 'System.Collections.Generic.List[string]'
    $stage = 'Reading pending reboot indicators'
    $reboot = Invoke-CimMethod -Namespace root\ccm\ClientSDK -ClassName CCM_ClientUtilities -MethodName DetermineIfRebootPending -OperationTimeoutSec 20
    if ((Get-RequiredProperty $reboot 'ReturnValue') -ne 0) { throw 'SCCM reboot query returned a failure code.' }
    if ((Get-RequiredProperty $reboot 'RebootPending') -or (Get-RequiredProperty $reboot 'IsHardRebootPending')) { $reasons.Add('SCCM client') }
    if (@($deployed | Where-Object { $_.EvaluationState -in @(8,9,10) }).Count) { $reasons.Add('SCCM update awaiting reboot') }
    foreach ($reason in @(Get-RegistryRebootReasons)) { $reasons.Add($reason) }
    $row.RebootPending = if ($reasons.Count) { 'Yes' } else { 'No' }
    $row.RebootReasons = $reasons -join '; '

    if ($missing.Count -or $reasons.Count) {
        Clear-VerificationRequest $row
        $row.Status = 'ACTION REQUIRED'
        $row.Reason = "Software Center-visible updates waiting: $($missing.Count). Pending reboot: $($row.RebootPending). $($row.RebootReasons)"
        return $row
    }
    if ($unknown.Count) { throw "$($unknown.Count) Software Center-visible updates have indeterminate compliance. No clean result can be established." }

    $stage = 'Verifying scan-completion evidence'
    if ($scanError) { throw $scanError }
    $after = Get-ScanSnapshot
    if ($before.Signature -ne $after.Signature) {
        $row.Status = 'NOT READY'; $row.Reason = 'Scan history or update-source metadata changed during assessment. Check again in the next wave.'; return $row
    }
    $sources = @($after.Sources); $history = @($after.History)
    $bootAfter = ConvertTo-UtcText (Get-CimInstance -ClassName Win32_OperatingSystem -OperationTimeoutSec 20).LastBootUpTime
    if ($bootAfter -ne $row.LastBootUtc) {
        # A changing observation cannot justify replacing an earlier request.
        $row.Status = 'NOT READY'; $row.Reason = 'Boot time changed during assessment. Any earlier scan request is retained.'
        $row.VerificationContextJson = ConvertTo-Json -InputObject ([ordered]@{ Decision = 'BOOT CHANGED DURING ASSESSMENT'; LoadedRequestUtc = $InputRow.ScanRequestedAtUtc; InitialBootUtc = $row.LastBootUtc; FinalBootUtc = $bootAfter }) -Compress
        return $row
    }
    $row.ScanEvidenceJson = ConvertTo-Json -InputObject @($history) -Compress -Depth 4
    $verification = Test-ScanVerification $row $sources $history $row.LastBootUtc
    $row.Verification = $verification
    # Retain the decision inputs BEFORE submission could replace their values.
    # This evidence distinguishes lost input tracking from actual context changes.
    $row.VerificationContextJson = ConvertTo-Json -InputObject ([ordered]@{
        Decision = $verification
        LoadedRequestUtc = $InputRow.ScanRequestedAtUtc
        SavedRequestBootUtc = $InputRow.ScanRequestBootUtc
        ObservedBootUtc = $row.LastBootUtc
        SavedBaselineJson = $InputRow.ScanBaselineJson
        ObservedSources = @($sources)
        ObservedHistory = @($history)
    }) -Depth 6 -Compress
    if ($verification -eq 'CONFIRMED') {
        $row.Status = 'PASS'; $row.Reason = 'Verification scan confirmed; no Software Center-visible updates waiting and no pending reboot.'; return $row
    }
    if ($row.ScanRequestedAtUtc) {
        # Never renew a pending request silently, including when a boot/source
        # mismatch is reported. Preserve the original boundary and show why it
        # cannot be confirmed instead of creating an endless request loop.
        $row.Status = 'VERIFICATION PENDING'
        $row.Reason = "Prior request retained. Verification: $verification. No additional scan requested."
        if ($verification -in @('BOOT CHANGED','SOURCE CHANGED')) {
            $row.Reason += ' Review VerificationContextJson before deliberately starting a new verification cycle.'
        }
        return $row
    }

    # Only an assessment with no existing request may establish a new baseline
    # and submit a scan. Context mismatches above never trigger another submission.
    $baseline = @($sources | ForEach-Object {
        $source = $_
        $match = @($history | Where-Object Id -eq $source.Id)
        if ($match.Count -gt 1) { throw 'Ambiguous scan history for an update source.' }
        [pscustomobject]@{ Id = $source.Id; Version = $source.Version; CompletedUtc = if ($match.Count) { $match[0].CompletedUtc } else { '' } }
    })
    $row.ScanBaselineJson = ConvertTo-Json -InputObject @($baseline) -Compress -Depth 4
    $row.ScanRequestBootUtc = $row.LastBootUtc
    $row.ScanRequestedAtUtc = [datetime]::UtcNow.ToString('o')
    $row.ScanRequestOutcome = 'Unconfirmed'
    $row.ScanRequestDetails = 'Submission started; provider acknowledgement not yet read.'
    $row.Verification = 'REQUEST OUTCOME UNKNOWN'
    $stage = 'Submitting SCCM verification scan'
    # Record the boundary before submission. If the response is lost or nonzero,
    # preserve the boundary and do not issue repeated requests automatically.
    $trigger = Invoke-CimMethod -Namespace root\ccm -ClassName SMS_Client -MethodName TriggerSchedule -Arguments @{ sScheduleID = '{00000000-0000-0000-0000-000000000113}' } -OperationTimeoutSec 20
    $acknowledgement = Get-ScanRequestAcknowledgement $trigger
    $row.ScanRequestOutcome = $acknowledgement.Outcome
    $row.ScanRequestDetails = $acknowledgement.Details
    if ($acknowledgement.Outcome -eq 'Rejected') {
        $row.Verification = 'REQUEST REJECTED'
        throw "Scan request returned failure code $($acknowledgement.Code). Request boundary retained; inspect client logs."
    }
    $row.Status = 'VERIFICATION PENDING'
    if ($acknowledgement.Outcome -eq 'Accepted') {
        $row.Verification = 'REQUESTED'
        $row.Reason = 'Scan request accepted. Use the unfinished CSV in the next wave to confirm completion.'
    }
    else {
        $row.Verification = 'REQUEST UNCONFIRMED'
        $row.Reason = 'Scan call returned without a usable acceptance code. Request may have been submitted; next wave must confirm completion. No automatic resubmission.'
    }
}
catch {
    $failure = $_
    $row.Status = 'UNABLE TO DETERMINE'; $row.Reason = "${stage}: $($failure.Exception.Message)"
    # Explicit text avoids ErrorRecord display formatting suppressing diagnostics.
    $row.Diagnostics = 'Stage={0}; ErrorId={1}; Category={2}; Exception={3}; Message={4}; Stack={5}' -f $stage,$failure.FullyQualifiedErrorId,$failure.CategoryInfo.Category,$failure.Exception.GetType().FullName,$failure.Exception.Message,$failure.ScriptStackTrace
}
$row
