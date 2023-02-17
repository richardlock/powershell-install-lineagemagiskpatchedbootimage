# Install-LineageMagiskPatchedBootImage PowerShell script

PowerShell script to download current LineageOS build, extract boot image, patch with Magisk, and flash patched boot image to Android device.

Based on a [bash script](https://github.com/NicolasWebDev/reinstall-magisk-on-lineageos) by NicolasWebDev,
which itself is based on the [Magisk installation guide](https://topjohnwu.github.io/Magisk/install.html).

Due to the lack of native [USB support in Windows Subsystem for Linux (WSL)](https://learn.microsoft.com/en-us/windows/wsl/connect-usb),
I ported the script to PowerShell and added some additional error checking for Windows users to easily upgrade LineageOS and repatch the boot image with Magisk.

## Usage

1. Open `'Settings > System > Updater'` on your LineageOS device. Download and install an update.

2. Reboot device and Magisk will show as no longer installed.

3. Connect your device to your computer.

4. Open a PowerShell prompt on your computer.

5. Download or clone the repository.

   ```powershell
   PS> git clone http://github.com/richardlock/Install-LineageMagiskPatchedBootImage
   ```

6. Get the device serial number of the connected LineageOS device.

   ```powershell
   PS> adb devices
   List of devices attached
   ABCD123456 device
   ```

7. Execute the script specifying the device serial number.

   ```powershell
   .\Install-LineageMagiskPatchedBootImage.ps1 -DeviceSerialNumber 'ABCD123456'
   ```

## Requirements

Android device requirements:
- LineageOS.
- Magisk.
- Rooted debugging enabled.

Windows device requirements:
- Android SDK Platform-Tools 'adb' and 'fastboot' (https://developer.android.com/studio/releases/platform-tools).
- Python 3 (https://www.python.org/downloads).
- PowerShell Logging module (https://www.powershellgallery.com/packages/Logging).