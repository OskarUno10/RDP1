# RdpFree / KallAncrit. Dependencies ONLY: no game, client, mods or license bypass.
param([switch]$DirectXOnly)
$XyTag='RdpFree:dependencies'
. "$PSScriptRoot/lib-common.ps1"
$ErrorActionPreference='Stop'
$root='C:\ProgramData\RdpFree\dependencies'
New-Item -ItemType Directory -Path $root -Force | Out-Null
foreach($dir in @("$env:SystemRoot\Temp",$env:TEMP,$env:TMP)) { if($dir){New-Item -ItemType Directory -Path $dir -Force | Out-Null} }
function Run-Installer([string]$File,[string[]]$Arguments,[int]$Seconds=180) {
  $p=Start-Process -FilePath $File -ArgumentList $Arguments -PassThru -NoNewWindow
  if(-not $p.WaitForExit($Seconds*1000)){ $p | Stop-Process -Force -ErrorAction SilentlyContinue; throw 'Installer timeout; periksa log lokal Windows.' }
  $p.WaitForExit(); return $p.ExitCode
}
function Get-MicrosoftInstaller([string]$Url,[string]$File) {
  if(-not(Get-File $Url $File 180)){throw 'Unduhan installer Microsoft gagal'}
  $sig=Get-AuthenticodeSignature $File
  if($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch 'Microsoft Corporation'){throw 'Signature Microsoft tidak valid; installer tidak dijalankan'}
}
function Missing-DirectX {
  foreach($folder in @('System32','SysWOW64')) {
    foreach($dll in @('d3dx9_25.dll','d3dx9_43.dll','d3dcompiler_43.dll','xinput1_3.dll')) {
      $file=Join-Path "$env:SystemRoot\$folder" $dll
      if(-not(Test-Path $file)){ "$folder/$dll" }
    }
  }
}
$report=@{status='pending';directx='pending';vcredist='not_requested';directplay='not_requested';netfx3='not_requested';note='';gta_installed=$false;samp_installed=$false;play_tested=$false}
try {
  if(@(Missing-DirectX).Count) {
    $package=Join-Path $root 'directx_Jun2010_redist.exe'
    Get-MicrosoftInstaller 'https://download.microsoft.com/download/8/4/a/84a35bf1-dafe-4ae8-82af-ad2ae20b6b14/directx_Jun2010_redist.exe' $package
    $extract=Join-Path $root 'directx'
    New-Item -ItemType Directory -Path $extract -Force | Out-Null
    $code=Run-Installer $package @('/Q',"/T:`"$extract`"",'/C') 90
    if($code -ne 0){throw "Ekstraksi DirectX gagal: $code"}
    $setup=Join-Path $extract 'DXSETUP.exe'
    if(-not(Test-Path $setup)){throw 'DXSETUP.exe tidak ditemukan'}
    $code=Run-Installer $setup @('/silent') 180
    Log "DXSETUP exit=$code"
    if($code -notin @(0,3010)){throw "DXSETUP gagal: $code. Log lokal: Windows\Logs\DirectX.log dan DXError.log. Tidak ada fallback WARP palsu."}
  }
  $missing=@(Missing-DirectX)
  if($missing.Count){throw ('Runtime DirectX belum lengkap: '+($missing -join ', '))}
  $report.directx='verified_x86_x64'; Log 'DirectX legacy x86 + x64 terverifikasi. Ini bukan verifikasi GPU atau game.'
  if(-not $DirectXOnly) {
    foreach($arch in @('x86','x64')) {
      $vc=Join-Path $root "vc_redist.$arch.exe"
      Get-MicrosoftInstaller "https://aka.ms/vs/17/release/vc_redist.$arch.exe" $vc
      $code=Run-Installer $vc @('/install','/quiet','/norestart') 180
      if($code -notin @(0,3010,1638)){throw "Visual C++ $arch gagal: $code"}
      $folder=if($arch -eq 'x86'){'SysWOW64'}else{'System32'}
      if(-not(Test-Path "$env:SystemRoot\$folder\vcruntime140.dll")){throw "Runtime VC++ $arch tidak ditemukan"}
    }
    $legacy=Join-Path $root 'vcredist2013_x86.exe'
    Get-MicrosoftInstaller 'https://aka.ms/highdpimfc2013x86enu' $legacy
    $code=Run-Installer $legacy @('/install','/quiet','/norestart') 180
    if($code -notin @(0,3010,1638) -or -not(Test-Path "$env:SystemRoot\SysWOW64\msvcr120.dll")){throw 'Runtime VC++ 2013 x86 belum terverifikasi'}
    $report.vcredist='verified_x86_x64_and_2013_x86'
    foreach($feature in @('DirectPlay','NetFx3')) {
      $key=if($feature -eq 'DirectPlay'){'directplay'}else{'netfx3'}
      try {
        $state=Get-WindowsOptionalFeature -Online -FeatureName $feature -ErrorAction Stop
        if($state.State -ne 'Enabled') {
          $code=Run-Installer 'dism.exe' @('/Online','/Enable-Feature',"/FeatureName:$feature",'/All','/NoRestart','/Quiet') 90
          Log "$feature DISM exit=$code"
        }
        $report[$key]="$( (Get-WindowsOptionalFeature -Online -FeatureName $feature -ErrorAction Stop).State )"
      } catch { $report[$key]='unavailable_or_source_required';Log "$feature belum tersedia; tidak dilabeli berhasil." }
    }
  }
  $report.status='dependencies_ready'
  $report.note='DirectX legacy diverifikasi x86/x64. GTA SA dan SA-MP dipasang manual dari sumber sah. Game, GPU, dan koneksi server belum diuji.'
} catch {
  $report.status='dependencies_failed';$report.note=$_.Exception.Message
  Update-Status @{samp=$report} | Out-Null
  throw
}
Update-Status @{samp=$report} | Out-Null
Log $report.note
