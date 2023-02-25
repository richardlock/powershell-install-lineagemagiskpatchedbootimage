<#
    .SYNOPSIS
    PowerShell script to download current LineageOS build, extract boot image, patch with Magisk, and flash patched boot image to Android device.

    .DESCRIPTION
    PowerShell script to download current LineageOS build, extract boot image, patch with Magisk, and flash patched boot image to Android device.
    Based on bash script by NicolasWebDev: https://github.com/NicolasWebDev/reinstall-magisk-on-lineageos

    .PARAMETER DeviceSerialNumber
    The device serial number obtained from the output of command 'adb devices'.

    .INPUTS
    None.

    .OUTPUTS
    None.

    .EXAMPLE
    PS> Install-LineageMagiskPatchedBootImage.ps1 -DeviceSerialNumber 'ABCD123456'

    .LINK
    http://github.com/richardlock/Install-LineageMagiskPatchedBootImage

    .NOTES
    Android device requirements:
      - LineageOS.
      - Magisk.
      - Rooted debugging enabled.

    Windows device requirements:
      - Android SDK Platform-Tools 'adb' and 'fastboot' (https://developer.android.com/studio/releases/platform-tools).
      - Python 3 (https://www.python.org/downloads).
      - PowerShell Logging module (https://www.powershellgallery.com/packages/Logging).
#>

param (
    [Parameter(
        HelpMessage = "The device serial number obtained from the output of command 'adb devices'.",
        Mandatory = $true
    )]
    [string]
    $DeviceSerialNumber
)

function Initialize-Logging {
    Import-Module Logging
    Set-LoggingDefaultLevel -Level 'INFO'
    Add-LoggingTarget -Name Console
    Write-Log -Level 'INFO' -Message 'Begin.'
}

function Confirm-DeviceSerialNumber ($DeviceSerialNumber) {
    $adbDevices = adb devices -l
    if ($adbDevices -match $DeviceSerialNumber) {
        Write-Log -Level 'INFO' -Message "Boot image will be patched on device:`n$($adbDevices | Select-String $DeviceSerialNumber)"
    }
    else {
        Throw "Device with serial number '$DeviceSerialNumber' is not connected."
    }
}

function Confirm-AdbRootedDebugging ($DeviceSerialNumber) {
    $adbRootedDebugging = adb -s $DeviceSerialNumber root
    if ($adbRootedDebugging -eq 'restarting adbd as root' -or
        $adbRootedDebugging -eq 'adbd is already running as root') {
        Write-Log -Level 'INFO' -Message 'Rooted debugging is enabled.'
    }
    else {
        Throw "Rooted debugging is not enabled.`n$adbRootedDebugging"
    }
}

function Confirm-MagiskBootPatchScript ($DeviceSerialNumber) {
    $adbListMagiskDirectory = adb -s $DeviceSerialNumber shell ls /data/adb/magisk/
    if ($adbListMagiskDirectory | Select-String 'boot_patch.sh') {
        Write-Log -Level 'INFO' -Message "Magisk 'boot_patch.sh' script exists."
    }
    else {
        Throw -Message "Magisk 'boot_patch.sh' script does not exist."
    }
}

function Confirm-Python {
    if (python3 --version | Select-String '3.') {
        Write-Log -Level 'INFO' -Message 'Python 3 is installed.'
    }
    else {
        Throw 'Python 3 is not installed.'
    }
}

function Install-PythonPackage ($packages) {
    foreach ($package in $packages) {
        if (-not (python3 -m pip list | Select-String $package)) {
            Write-Log -Level 'INFO' -Message "Installing python '$package' package."
            python3 -m pip install $package
        }
        else {
            Write-Log -Level 'INFO' -Message "Python '$package' package is installed."
        }
    }
}

function New-TempDirectory {
    $randomString = -join (1..20 | ForEach-Object {[char]((97..122) + (48..57) | Get-Random)})
    New-Item -Path $randomString -ItemType Directory
}

function Get-LineageBuildFile ($DeviceSerialNumber, $outFile) {
    $lineageDevice = $(adb -s $DeviceSerialNumber shell getprop ro.lineage.device) -replace "`n|`r|`t",''
    $lineageVersion = $(adb -s $DeviceSerialNumber shell getprop ro.lineage.version) -replace "`n|`r|`t",''
    $lineageBuildUri = ((Invoke-WebRequest -Uri "https://download.lineageos.org/$lineageDevice").links |
        Where-Object {$_.innerText -match "$lineageVersion-signed.zip"} | Select-Object -First 1).href

    $ProgressPreference = 'SilentlyContinue'
    Write-Log -Level 'INFO' -Message "Downloading Lineage build from '$lineageBuildUri'."
    Invoke-WebRequest -Uri $lineageBuildUri -OutFile $outFile
    $ProgressPreference = 'Continue'

    Get-Item -Path $outFile
}

function Expand-BootImage ($DeviceSerialNumber, $zipFilePath, $outDirectory) {
    Write-Log -Level 'INFO' -Message "Opening '$zipFilePath'."
    Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
    $zipFile = [System.IO.Compression.ZipFile]::OpenRead($zipFilePath)
    
    if ($zipFile.Entries.Name -contains 'payload.bin') {
       $fileName = 'payload.bin' 
    }
    elseif ($zipFile.Entries.Name -contains 'boot.img') {
        $fileName = 'boot.img'
    }
    else {
        Throw 'Lineage build file does not contain boot image.'
    }
    
    Write-Log -Level 'INFO' -Message "Extracting '$fileName' from '$zipFilePath'."
    [System.IO.Compression.ZipFileExtensions]::ExtractToFile($($zipFile.Entries |
        Where-Object {$_.Name -eq $fileName}) , "$outDirectory/$fileName")
    $zipFile.Dispose()
        
    if ($fileName -eq 'payload.bin') {
        Invoke-WebRequest -Uri 'https://github.com/LineageOS/scripts/archive/refs/heads/master.zip' -OutFile "$outDirectory/scripts.zip"
        [System.IO.Compression.ZipFile]::ExtractToDirectory("$outDirectory/scripts.zip", $outDirectory)
        python3 "$outDirectory/scripts-master/update-payload-extractor/extract.py" --partitions boot --output_dir $outDirectory "$outDirectory/payload.bin"
    }

    Get-Item -Path "$outDirectory/boot.img"
}

function Copy-FileToDevice ($DeviceSerialNumber, $sourceFilePath, $destinationFilePath) {
    Write-Log -Level 'INFO' -Message "Pushing unpatched boot image from '$sourceFilePath' to '$destinationFilePath'."
    adb -s $DeviceSerialNumber push $sourceFilePath $destinationFilePath
}

function Invoke-MagiskBootPatchScript ($sourceFilePath, $destinationFilePath) {
    Write-Log -Level 'INFO' -Message "Patching boot image '$sourceFilePath' to '$destinationFilePath'."
    adb -s $DeviceSerialNumber shell '/data/adb/magisk/boot_patch.sh' $sourceFilePath
    adb -s $DeviceSerialNumber shell mv '/data/adb/magisk/new-boot.img' $destinationFilePath
}

function Copy-FileToComputer ($DeviceSerialNumber, $sourceFilePath, $destinationFilePath) {
    Write-Log -Level 'INFO' -Message "Pulling patched boot image from '$sourceFilePath' to '$destinationFilePath'."
    adb -s $DeviceSerialNumber pull $sourceFilePath $destinationFilePath
}

function Restart-Bootloader ($DeviceSerialNumber) {
    Write-Log -Level 'INFO' -Message "Rebooting device to bootloader."
    adb -s $DeviceSerialNumber reboot bootloader
}

function Invoke-FlashBootImage ($DeviceSerialNumber, $patchedBootImagePath) {
    Write-Log -Level 'INFO' -Message "Waiting for device to restart in fastboot mode."
    $endTime = (Get-Date).AddSeconds(60)
    do {
        $fastbootDevices = fastboot devices
    } until ($fastbootDevices -match $DeviceSerialNumber -or ((Get-Date) -ge $endTime))

    Write-Log -Level 'INFO' -Message "Flashing patched boot image '$patchedBootImagePath'."
    fastboot -s $DeviceSerialNumber flash boot $patchedBootImagePath
}

function Restart-Device ($DeviceSerialNumber) {
    Write-Log -Level 'INFO' -Message "Rebooting device."
    fastboot -s $DeviceSerialNumber reboot
}

function Remove-Directory ($directoryPath) {
    if (-not [string]::IsNullOrEmpty($directoryPath) -and (Test-Path -Path $directoryPath)) {
        Write-Log -Level 'INFO' -Message "Removing directory '$directoryPath'."
        Remove-Item -Path $directoryPath -Recurse -Force -Confirm:$false
    }
}

# Main
try {
    Initialize-Logging

    Confirm-DeviceSerialNumber $DeviceSerialNumber
    Confirm-AdbRootedDebugging $DeviceSerialNumber
    Confirm-MagiskBootPatchScript $DeviceSerialNumber
    Confirm-Python
    Install-PythonPackage @('protobuf<3.20', 'six')
    
    $tempDirectory = New-TempDirectory
    $lineageBuildFile = Get-LineageBuildFile $DeviceSerialNumber "$($tempDirectory.FullName)/lineage.zip"
    $bootImage = Expand-BootImage $DeviceSerialNumber $lineageBuildFile.FullName $tempDirectory
    
    Copy-FileToDevice $DeviceSerialNumber $bootImage.FullName '/sdcard/Download/boot.img'
    Invoke-MagiskBootPatchScript '/sdcard/Download/boot.img' '/sdcard/Download/patched-boot.img'
    Copy-FileToComputer $DeviceSerialNumber '/sdcard/Download/patched-boot.img' "$tempDirectory/patched-boot.img"
    
    Restart-Bootloader $DeviceSerialNumber
    Invoke-FlashBootImage $DeviceSerialNumber "$tempDirectory/patched-boot.img"
    Restart-Device $DeviceSerialNumber
}
catch {
    Write-Log -Level 'ERROR' -Message "$_"
}
finally {
    Remove-Directory $tempDirectory
    Write-Log -Level 'INFO' -Message 'End.'
    Wait-Logging
}
