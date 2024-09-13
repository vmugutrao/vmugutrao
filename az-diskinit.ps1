# Set LocalAccountTokenFilterPolicy to 1 and Enable winrm
$path="C:\Scripts\diskinit\Logs\";
                if( Test-Path $path ) { 
                    Write-Host "directory already exists" 
                } 
                else { 
                    mkdir $path
                }
$Transcript = "C:\Scripts\diskinit\Logs\disinit.txt"
Start-Transcript -Path $Transcript -Append
$token_path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
$token_prop_name = "LocalAccountTokenFilterPolicy"
$token_key = Get-Item -Path $token_path
$token_value = $token_key.GetValue($token_prop_name, $null)
if ($token_value -ne 1) {
    Write-Host "Setting LocalAccountTokenFilterPolicy to 1"
    if ($null -ne $token_value) {
        Remove-ItemProperty -Path $token_path -Name $token_prop_name
    }
    New-ItemProperty -Path $token_path -Name $token_prop_name -Value 1 -PropertyType DWORD > $null
}

Set-NetFirewallProfile  -Enabled  false
#winrm quickconfig
Set-Item -Path WSMan:\localhost\Service\Auth\Basic -Value $true
winrm set winrm/config/service '@{AllowUnencrypted="true"}'

$cd = $NULL
$cd = Get-WMIObject -Class Win32_CDROMDrive -ComputerName $env:COMPUTERNAME -ErrorAction continue


if ($cd) {
    write-host "CD drive exists"
    $driveletter = $cd.Drive
    Set-WmiInstance -InputObject ( Get-WmiObject -Class Win32_volume -Filter "DriveLetter ='$driveletter'" ) -Arguments @{DriveLetter='X:'}
}


$obj1_properties = @{diskname = "NA"; drivelabel = "NA"; driveletter = "NA";diskSizeGB = "NA"; lun = "NA"}    
$disks = Invoke-RestMethod -Headers @{"Metadata"="true"} -Method GET -Uri "http://169.254.169.254/metadata/instance?api-version=2023-11-15"

$disks_metadata = @()
$DataDisks = $disks.compute.storageProfile.dataDisks
foreach($disk in $DataDisks) {
    $obj1 = @()
    $obj1 = New-Object -TypeName psobject -Property $obj1_properties
    $obj1.diskname = $disk.name
    $obj1.drivelabel = ($disk.name -split '-')[1]
    $obj1.driveletter = ($disk.name -split '-')[2]
    $obj1.diskSizeGB = $disk.diskSizeGB
    $obj1.lun = $disk.lun
    $disks_metadata += $obj1
}
#$disks_metadata

# Get lun numbers disks with PartitionStyle 'RAW'
$datadisks = @()
$obj2_properties = @{disknumber = "NA"; driveletter = "NA"; drivelabel = "NA"; diskSizeGB = "NA"; lun = "NA"}
$rawDisks = Get-Disk | Where-Object { $_.PartitionStyle -eq 'RAW' }
foreach ($raw_disk in $rawDisks) {
    $obj2 = @()
    $obj2 = New-Object -TypeName psobject -Property $obj2_properties
    $raw_diskInfo = Get-WmiObject -Class Win32_DiskDrive | Where-Object { $_.DeviceID -eq "\\.\PHYSICALDRIVE$($raw_disk.Number)" }
    if ($raw_diskInfo) 
        {
        $obj2.lun = $raw_diskInfo.ScsiLogicalUnit
        $obj2.diskSizeGB = [math]::Round($raw_disk.Size / 1GB, 2)  # Convert size to GB
        $obj2.disknumber = $raw_disk.disknumber
        $obj2.driveletter = ($disks_metadata | Where-Object { $_.lun -eq $raw_diskInfo.ScsiLogicalUnit }).driveletter
        $obj2.drivelabel = ($disks_metadata | Where-Object { $_.lun -eq $raw_diskInfo.ScsiLogicalUnit }).drivelabel
        $datadisks += $obj2
    } else {
        Write-Output "WMI info not found for disk $($raw_disk.DeviceID)"
    }
    
}

#Format
If($datadisks.Count -gt 0)
   {
   write-Host "$($DataDisks.Count) additional disk/s found on instance"
   $UsedDriveLetters = (Get-Partition).DriveLetter
   foreach($disk in $datadisks)
       {
       Write-Host "Formatting disk $($disk.disknumber) as $($disk.drivelabel):$($disk.driveletter)"
       If($UsedDriveLetters -contains $($disk.driveletter) -or $null -eq $($disk.driveletter)) {Write-Host "$($disk.driveletter) already present or blank in metadata";continue}
       $DiskStatus = Get-Disk -Number $($disk.disknumber)
       If($DiskStatus.PartitionStyle -eq 'raw') {$null = $DiskStatus | Initialize-Disk -PartitionStyle GPT}
       $Null = New-Partition -disknumber $($disk.disknumber) -usemaximumsize -DriveLetter $($disk.driveletter) | format-volume -filesystem NTFS -newfilesystemlabel (($disk.drivelabel).ToUpper()) -AllocationUnitSize 65536
       Write-Host "Successfully created a partition on Disk $($disk.Number) as $($label)"
   }
}
else
   {
   Write-Host "No additiona disks found on $ServerName" -ForegroundColor Yellow
}
