<#
.SYNOPSIS
  Detects what kind of machine this is, and which provisioning mode fits it.

.DESCRIPTION
  Dot-source this file to get Get-MachineProfile and Show-MachineProfile.

  The repo has two modes:

    Parallels - the lean profile. No nested virtualization, so no WSL, no
                Hyper-V, no Docker. This is what config\dev-config.winget alone
                provides, and it is the historical behavior of this repo.

    Native    - anything that is not a Parallels guest: a physical box, or a VM
                on a hypervisor that exposes virtualization to the guest. Adds
                config\native.winget and config\native-post.winget on top of the
                base config: WSL + Ubuntu, Docker Desktop, Hyper-V, Sandbox.

  Must stay Windows PowerShell 5.1 compatible - install.ps1 dot-sources this
  before pwsh 7 exists. No ternaries, no null-coalescing, no -AsHashtable.

.EXAMPLE
  . .\lib\Get-MachineProfile.ps1
  Get-MachineProfile | Format-List

.EXAMPLE
  .\bootstrap.ps1 -DetectOnly      # prints the report and changes nothing
#>

function Get-MachineProfile {
    [CmdletBinding()]
    param()

    $reasons = New-Object System.Collections.Generic.List[string]

    $cs   = Get-CimInstance -ClassName Win32_ComputerSystem  -ErrorAction SilentlyContinue
    $bios = Get-CimInstance -ClassName Win32_BIOS            -ErrorAction SilentlyContinue
    $os   = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
    $cpu  = @(Get-CimInstance -ClassName Win32_Processor -ErrorAction SilentlyContinue) |
                Select-Object -First 1

    $manufacturer = ''
    $model        = ''
    if ($cs) {
        $manufacturer = [string]$cs.Manufacturer
        $model        = [string]$cs.Model
    }
    $biosVendor = ''
    if ($bios) { $biosVendor = [string]$bios.Manufacturer }

    # --- which hypervisor, if any ---------------------------------------------
    # Vendors are inconsistent about which SMBIOS field they stamp, so all three
    # identity strings are matched together rather than field by field.
    $idString = ($manufacturer, $model, $biosVendor) -join ' '

    $platform = 'Physical'
    if     ($idString -match 'Parallels')          { $platform = 'Parallels' }
    elseif ($idString -match 'VMware')             { $platform = 'VMware' }
    elseif ($idString -match 'VirtualBox|innotek') { $platform = 'VirtualBox' }
    elseif ($idString -match 'QEMU|KVM|Bochs')     { $platform = 'QEMU/KVM' }
    elseif ($idString -match 'Xen')                { $platform = 'Xen' }
    elseif ($idString -match 'Amazon EC2')         { $platform = 'Amazon EC2' }
    elseif ($idString -match 'Google')             { $platform = 'Google Compute Engine' }
    elseif ($model    -match 'Virtual Machine')    { $platform = 'Hyper-V' }

    # Second signal: Parallels Tools registers services prefixed prl_. A guest
    # configured with SMBIOS passthrough reports the Mac's real manufacturer
    # instead of Parallels', and would otherwise read as physical.
    if ($platform -eq 'Physical') {
        $prl = @(Get-CimInstance -ClassName Win32_Service -Filter "Name LIKE 'prl%'" `
                    -ErrorAction SilentlyContinue)
        if ($prl.Count -gt 0) {
            $platform = 'Parallels'
            $reasons.Add('Parallels Tools services (prl_*) are present')
        }
    }

    $isParallels = ($platform -eq 'Parallels')
    $isVirtual   = ($platform -ne 'Physical')

    # --- architecture ----------------------------------------------------------
    # PROCESSOR_ARCHITECTURE reports the *process* architecture. In a 32-bit or
    # emulated process it lies; ARCHITEW6432 carries the real one when it does.
    $arch = $env:PROCESSOR_ARCHITECTURE
    if ($env:PROCESSOR_ARCHITEW6432) { $arch = $env:PROCESSOR_ARCHITEW6432 }
    $isArm = ($arch -match 'ARM')

    # --- edition ---------------------------------------------------------------
    $sku     = 0
    $caption = ''
    if ($os) {
        $sku     = [int]$os.OperatingSystemSKU
        $caption = [string]$os.Caption
    }
    # SKUs that ship Hyper-V and Windows Sandbox. Home (98-101) does not.
    $proSkus = @(4, 27, 48, 49, 72, 79, 80, 84, 161, 162, 164, 175)
    $isProOrBetter = (($proSkus -contains $sku) -or
                      ($caption -match 'Pro|Enterprise|Education|Server'))

    # --- can this machine actually run a hypervisor workload? ------------------
    # vmcompute (Hyper-V Host Compute Service) exists once Virtual Machine
    # Platform is active - the same test upstream's WSL phases use.
    $slat   = $false
    $virtFw = $false
    if ($cpu) {
        $slat   = [bool]$cpu.SecondLevelAddressTranslationExtensions
        $virtFw = [bool]$cpu.VirtualizationFirmwareEnabled
    }
    $hypervisorPresent = $false
    if ($cs) { $hypervisorPresent = [bool]$cs.HypervisorPresent }

    $vmcompute = [bool](Get-CimInstance -ClassName Win32_Service -Filter "Name='vmcompute'" `
                           -ErrorAction SilentlyContinue)

    # VirtualizationFirmwareEnabled reads False once Hyper-V has claimed the
    # CPU, so any one of these four being true is enough.
    $virtAvailable = ($slat -or $virtFw -or $hypervisorPresent -or $vmcompute)

    # --- decide ----------------------------------------------------------------
    if ($isParallels) {
        $mode = 'Parallels'
        $reasons.Add('Parallels guest - nested virtualization is not available, so WSL/Docker/Hyper-V are skipped')
    } else {
        $mode = 'Native'
        if ($isVirtual) {
            $reasons.Add("Virtual machine on $platform - not Parallels, so the full stack is attempted")
        } else {
            $reasons.Add('Physical machine - the full stack applies')
        }
    }

    if ($mode -eq 'Native') {
        if (-not $virtAvailable) {
            $reasons.Add('No SLAT/virtualization extensions visible - WSL and Docker will likely fail; enable virtualization in firmware (or nested virt on the host)')
        }
        if (-not $isProOrBetter) {
            $reasons.Add('Not Pro/Enterprise/Education - Hyper-V and Windows Sandbox are unavailable on this edition and will be skipped')
        }
        if ($isArm) {
            $reasons.Add('ARM64 - WSL and Docker Desktop both ship ARM64 builds, but verify package availability')
        }
    }

    return [pscustomobject]@{
        Mode              = $mode
        Platform          = $platform
        IsParallels       = $isParallels
        IsVirtual         = $isVirtual
        Manufacturer      = $manufacturer
        Model             = $model
        Architecture      = $arch
        IsArm             = $isArm
        Edition           = $caption
        EditionSku        = $sku
        IsProOrBetter     = $isProOrBetter
        VirtAvailable     = $virtAvailable
        VmComputePresent  = $vmcompute
        SupportsWsl       = ($mode -eq 'Native' -and $virtAvailable)
        SupportsHyperV    = ($mode -eq 'Native' -and $virtAvailable -and $isProOrBetter)
        Reasons           = $reasons.ToArray()
    }
}

function Show-MachineProfile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Machine,

        # The mode actually being used, when it differs from what was detected.
        [string]$EffectiveMode
    )

    Write-Host ''
    Write-Host '  Machine profile' -ForegroundColor White

    $rows = [ordered]@{
        'Platform'     = $Machine.Platform
        'Hardware'     = ($Machine.Manufacturer + ' / ' + $Machine.Model).Trim(' /')
        'Edition'      = $Machine.Edition
        'Architecture' = $Machine.Architecture
        'Detected mode'= $Machine.Mode
    }
    foreach ($k in $rows.Keys) {
        Write-Host ('    {0,-14} {1}' -f $k, $rows[$k]) -ForegroundColor Gray
    }

    if ($EffectiveMode -and $EffectiveMode -ne $Machine.Mode) {
        Write-Host ('    {0,-14} {1}  (overridden)' -f 'Using mode', $EffectiveMode) -ForegroundColor Yellow
    }

    $mode = $Machine.Mode
    if ($EffectiveMode) { $mode = $EffectiveMode }

    if ($mode -eq 'Native') {
        Write-Host ''
        Write-Host '    Native extras:' -ForegroundColor Gray
        $wsl = 'no'
        if ($Machine.SupportsWsl) { $wsl = 'yes' }
        $hv = 'no'
        if ($Machine.SupportsHyperV) { $hv = 'yes' }
        Write-Host ('      WSL + Ubuntu + Docker Desktop : {0}' -f $wsl) -ForegroundColor Gray
        Write-Host ('      Hyper-V + Windows Sandbox     : {0}' -f $hv) -ForegroundColor Gray
    }

    foreach ($r in $Machine.Reasons) {
        Write-Host "    - $r" -ForegroundColor DarkGray
    }
    Write-Host ''
}
