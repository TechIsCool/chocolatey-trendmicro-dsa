Add-Type -Assembly System.IO.Compression.FileSystem
Set-Location $PSScriptRoot

$Params = @{
  Algorithm = 'SHA256';
  LocalZip = @{};
  FileName = @{};
  LocalFile = @{};
  URL = @{};
  ZipHash = @{};
  FileHash = @{};
  ProductCode = @{};
  Object = @{};
}
$Package     = 'trendmicro-dsa'
$feed     = 'https://s3.amazonaws.com/ds-dlc-feed-src/en-us/DeepSecurityInventory_dlc_fp.xml'
# $feed = 'https://s3.amazonaws.com/ds-dlc-feed-src/en-us/DeepSecurityInventory_dlc_10_0.xml'

$FeedFilter = @{
  Platform = 'Windows';
  Product = 'Agent';
  }

Try{ 
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  [xml]$Results = $(Invoke-WebRequest -Uri $feed -ErrorAction Stop).Content 
}
Catch [System.Exception]{ 
  $WebReqErr = $error[0] | Select-Object * | Format-List -Force 
  Write-Error "An error occurred while attempting to connect to the requested site.  The error was $WebReqErr.Exception" 
}

$FilteredResults = $Results.feed.entry | `
  Where-Object {$_.platform -eq $FeedFilter['Platform'] -and $_.product -eq $FeedFilter['Product']}


$Params['Object']['x86'] = $($FilteredResults | `
  Where-Object {$_.arch -eq 'i386'}) | `
  Sort-Object {$_.version.major, $_.version.minor, $_.version.sp, $_.version.build} -Descending | `
  Select-Object -First 1

$Params['Object']['x64'] = $($FilteredResults | `
  Where-Object {$_.arch -eq 'x86_64'}) | `
  Sort-Object {$_.version.major, $_.version.minor, $_.version.sp, $_.version.build} -Descending | `
  Select-Object -First 1

$Version = $Params['Object']['x64'] | % {"$($_.version.major).$($_.version.minor).$($_.version.sp).$($_.version.build)"}
$ReleaseNotes = $Params['Object']['x64'].readme

Write-Output `
  $Package `
  "Release Version: $Version" `
  "Release Notes: $ReleaseNotes"

New-Item `
  -ItemType Directory `
  -Path `
    "$PSScriptRoot\temp", `
    "$PSScriptRoot\output\binaries", ` 
    "$PSScriptRoot\output\tools\" `
  -ErrorAction SilentlyContinue | Out-Null


foreach ($OS in 'x86','x64') {
  $Params['URL'][$OS] = $Params['Object'][$OS].download
  $Params['LocalZip'][$OS] = "$PSScriptRoot\temp\$($Params['Object'][$OS].pkginfo.name)"

  Invoke-WebRequest `
   -Uri $Params['URL'][$OS] `
   -OutFile $Params['LocalZip'][$OS]
  Write-Output "Downloaded $OS from $($Params['URL'][$OS])"

  $Params['ZipHash'][$OS] = Get-FileHash `
    -Path $Params['LocalZip'][$OS] `
    -Algorithm $Params['Algorithm']

  if($($Params['ZipHash'][$OS].Hash) -ne $Params['Object'][$OS].pkginfo.sha256){ 
    Write-Error "Checksum does not Match for $($Params['URL'][$OS])"
  }
  
  $zip = [IO.Compression.ZipFile]::OpenRead($Params['LocalZip'][$OS])
  $zip.Entries | `
    Where {
      $_.Name -like '*.msi'
    } | `
    foreach {
      [System.IO.Compression.ZipFileExtensions]::ExtractToFile($_, "$PSScriptRoot\output\binaries\$($_.Name)", $true)
      $Params['LocalFile'][$OS] =  "$PSScriptRoot\output\binaries\$($_.Name)"
      $Params['FileName'][$OS] = $_.Name
    }
  $zip.Dispose()
  $Params['LocalFile'][$OS]

  $Params['FileHash'][$OS] = Get-FileHash `
    -Path $Params['LocalFile'][$OS] `
    -Algorithm $Params['Algorithm']
  Write-Output "Created $OS $($Params['Algorithm']): $($Params['FileHash'][$OS].Hash)"

  $Params['ProductCode'][$OS] = $(.\Get-MSIFileInformation.ps1 -Path $Params['LocalFile'][$OS] -Property ProductCode)[3]
  Write-Output "Found $OS ProductCode: $($Params['ProductCode'][$OS])"
}


$(Get-Content -Path "$PSScriptRoot\templates\$Package.nuspec") `
  -replace '##VERSION##', $Version `
  -replace '##RELEASENOTES##', $ReleaseNotes | `
  Out-File "$PSScriptRoot\output\$Package.nuspec"
Write-Output "Created output\$Package.nuspec"

$(Get-Content -Path "$PSScriptRoot\templates\chocolateyInstall.ps1") `
  -replace '##PACKAGENAME##', $Package `
  -replace '##FILEx86##', $Params['FileName']['x86'] `
  -replace '##FILEx64##', $Params['FileName']['x64'] `
  -replace '##SHA256x86##', $Params['FileHash']['x86'].Hash `
  -replace '##SHA256x64##', $Params['FileHash']['x64'].Hash | `
  Out-File "$PSScriptRoot\output\tools\chocolateyInstall.ps1"
Write-Output 'Created output\tools\chocolateyInstall.ps1'


$(Get-Content -Path "$PSScriptRoot\templates\chocolateyUninstall.ps1") `
  -replace '##PACKAGENAME##', $Package `
  -replace '##PRODUCTCODEx86##', $Params['ProductCode']['x86'] `
  -replace '##PRODUCTCODEx64##', $Params['ProductCode']['x64'] | `
  Out-File "$PSScriptRoot\output\tools\chocolateyUninstall.ps1"
Write-Output 'Created output\tools\chocolateyUninstall.ps1'

Set-Item -Path ENV:NUPKG -Value "$Package.$Version.nupkg"