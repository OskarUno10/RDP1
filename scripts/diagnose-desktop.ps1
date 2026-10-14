# RdpFree / KallAncrit. Local diagnostics only; no credentials, uploads or reboot.
param([switch]$RestartExplorer)
$ErrorActionPreference='Stop'
$session=(Get-Process -Id $PID).SessionId
if($RestartExplorer){
  if($session -eq 0){throw 'Jalankan pemulihan dari sesi RDP pengguna, bukan service/Actions.'}
  Get-Process explorer -ErrorAction SilentlyContinue | Where-Object SessionId -eq $session | Stop-Process -Force -ErrorAction SilentlyContinue
  Start-Process explorer.exe
  Write-Host 'Explorer sesi ini dimulai ulang. Tidak menjalankan logout, reboot, atau restart layanan RDP.'
}
$root='C:\ProgramData\RdpFree\Diagnostics'
New-Item -ItemType Directory -Path $root -Force | Out-Null
$os=Get-CimInstance Win32_OperatingSystem
$apps=foreach($key in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*','HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*')){
 Get-ItemProperty $key -ErrorAction SilentlyContinue | Where-Object DisplayName | Select-Object DisplayName,DisplayVersion,Publisher,InstallDate
}
$events=foreach($log in @('Application','System')){
 Get-WinEvent -FilterHashtable @{LogName=$log;StartTime=(Get-Date).AddHours(-24);Level=@(1,2)} -MaxEvents 30 -ErrorAction SilentlyContinue | ForEach-Object {
   # Do not export raw event messages, command lines, environment or account names.
   $details=@{}
   try{[xml]$xml=$_.ToXml();foreach($item in $xml.Event.EventData.Data){if($item.Name -in @('AppName','ModuleName','ExceptionCode')){$details[$item.Name]=$item.'#text'}}}catch{}
   @{time=$_.TimeCreated.ToUniversalTime().ToString('o');id=$_.Id;provider=$_.ProviderName;details=$details}
 }
}
$dlls=foreach($folder in @('System32','SysWOW64')){foreach($dll in @('d3d9.dll','d3dx9_25.dll','d3dx9_43.dll','xinput1_3.dll','vcruntime140.dll','msvcr120.dll')){@{file="$folder/$dll";exists=(Test-Path "$env:SystemRoot\$folder\$dll")}}}
$report=@{created_at=(Get-Date).ToUniversalTime().ToString('o');os=$os.Caption;version=$os.Version;session_id=$session;drivers=@(Get-CimInstance Win32_VideoController | Select-Object Name,DriverVersion,Status);processes=@(Get-Process -ErrorAction SilentlyContinue | Where-Object {$_.SessionId -eq $session -and $_.ProcessName -match '^(explorer|dwm|gta_sa|samp|RobloxPlayerBeta)$'} | Select-Object ProcessName,Id,Responding);runtimes=@($dlls);installed_apps=@($apps | Sort-Object InstallDate -Descending);recent_errors=@($events)}
$file=Join-Path $root ('desktop-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'.json')
$report | ConvertTo-Json -Depth 7 | Set-Content $file -Encoding utf8
Write-Host "Diagnosis disimpan lokal: $file"
Write-Host 'Periksa laporan sebelum membagikan. Tidak ada file yang diunggah otomatis. Runtime tersedia bukan bukti game berhasil dimainkan.'
