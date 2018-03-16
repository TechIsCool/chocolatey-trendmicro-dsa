$package = '##PACKAGENAME##'

$launch_path = "$(Split-Path -parent $MyInvocation.MyCommand.Definition)"

$choco_params = @{
  PackageName = $package;
  FileType       = 'msi';
  SilentArgs     = '/qb'
  file           = "$launch_path\..\binaries\##FILEx86##";
  file64         = "$launch_path\..\binaries\##FILEx64##";
  checksum       = '##SHA256x86##'
  checksumType   = 'sha256'
  checksum64     = '##SHA256x64##'
  checksumType64 = 'sha256'
  ValidExitCodes = @(0)
}

Install-ChocolateyPackage @choco_params

