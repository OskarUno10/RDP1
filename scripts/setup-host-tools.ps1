# RdpFree / KallAncrit — verified tools for development, not a public relay.
$XyTag='RdpFree:host-tools'
. "$PSScriptRoot/lib-common.ps1"
$ErrorActionPreference='Stop'
$root='C:\ProgramData\RdpFree\host-tools'
New-Item -ItemType Directory -Path $root -Force | Out-Null
$report=[ordered]@{winrar='pending';vcredist='pending';xampp='pending';firewall7777='pending';errors=@();public_port=$false}
function Fetch-Pinned($Url,$File,$Hash) {
  if (-not (Get-File $Url $File 300)) { throw "Download failed: $Url" }
  if ((Get-FileHash $File -Algorithm SHA256).Hash -ne $Hash) { throw 'Installer SHA256 mismatch; execution refused' }
}
function Install-Wait($File,[string[]]$Arguments,[int]$Seconds=300) {
  $p=Start-Process -FilePath $File -ArgumentList $Arguments -PassThru
  if (-not $p.WaitForExit($Seconds*1000)) { & taskkill.exe /PID $p.Id /T /F | Out-Null; throw 'Installer timed out' }
  $p.WaitForExit(); if ($p.ExitCode -notin @(0,3010,1638)) { throw "Installer exit=$($p.ExitCode)" }
  if ($p.ExitCode -eq 3010) { Log 'Installer requests reboot; no automatic reboot performed.' }
}
function Check-Command($File,[string[]]$Arguments) {
  if (-not (Test-Path $File)) { throw "Missing executable: $File" }
  $stdout=Join-Path $root 'command.stdout.txt';$stderr=Join-Path $root 'command.stderr.txt'
  $p=Start-Process -FilePath $File -ArgumentList $Arguments -WorkingDirectory (Split-Path $File) -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
  if (-not $p.WaitForExit(30000)) { & taskkill.exe /PID $p.Id /T /F | Out-Null; throw "Verification timeout: $File" }
  $p.WaitForExit()
  if ($p.ExitCode -ne 0) { throw "Verification failed: $File, exit=$($p.ExitCode)" }
  Log ((Get-Content $stdout -TotalCount 2 -ErrorAction SilentlyContinue) -join ' ')
}
try {
  $file=Join-Path $root 'winrar-7.23.exe'
  # Pinned to microsoft/winget-pkgs RARLab.WinRAR 7.23.0, English x64.
  Fetch-Pinned 'https://www.rarlab.com/rar/winrar-x64-723.exe' $file '8FF0DAF3ED564CC743C0E23FF2E253997FFC74460F9673F0B6DD037B2DB4CE7B'
  Install-Wait $file @('-s1')
  $winrar="$env:ProgramFiles\WinRAR\WinRAR.exe"
  if (-not (Test-Path $winrar)) { throw 'WinRAR.exe missing after installation' }
  $version=(Get-Item $winrar).VersionInfo.FileVersion
  if ([version]([regex]::Match($version,'\d+(\.\d+)+').Value) -lt [version]'7.23') { throw 'WinRAR version older than requested' }
  $sample=Join-Path $root 'archive-test.txt'; 'RdpFree archive verification' | Set-Content $sample
  $archive=Join-Path $root 'archive-test.rar'
  Check-Command "$env:ProgramFiles\WinRAR\Rar.exe" @('a','-idq',"`"$archive`"","`"$sample`"")
  Check-Command "$env:ProgramFiles\WinRAR\Rar.exe" @('t','-idq',"`"$archive`"")
  $report.winrar="verified $version (vendor trial; license not included)"
} catch { $report.winrar='failed';$report.errors+= "WinRAR: $($_.Exception.Message)" }
try {
  foreach ($arch in @('x86','x64')) {
    $file=Join-Path $root "vc_redist.$arch.exe"
    if (-not (Get-File "https://aka.ms/vs/17/release/vc_redist.$arch.exe" $file 180)) { throw "VC++ $arch download failed" }
    $sig=Get-AuthenticodeSignature $file
    if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch 'Microsoft Corporation') { throw 'Invalid Microsoft installer signature' }
    Install-Wait $file @('/install','/quiet','/norestart')
    $folder=if ($arch -eq 'x86') {'SysWOW64'} else {'System32'}
    foreach ($name in @('vcruntime140.dll','msvcp140.dll')) {
      if (-not (Test-Path "$env:WINDIR\$folder\$name")) { throw "VC++ $arch runtime missing: $name" }
    }
    $expected=[version]([regex]::Match((Get-Item $file).VersionInfo.ProductVersion,'\d+(\.\d+)+').Value)
    $actual=[version]([regex]::Match((Get-Item "$env:WINDIR\$folder\vcruntime140.dll").VersionInfo.FileVersion,'\d+(\.\d+)+').Value)
    if ($actual -lt $expected) { throw "VC++ $arch installed version is older than downloaded package" }
    Log "VC++ $arch verified version $actual"
  }
  $report.vcredist='verified_current_v14_x86_x64'
} catch { $report.vcredist='failed';$report.errors+="VC++: $($_.Exception.Message)" }
try {
  if (-not (Test-Path 'C:\xampp\xampp-control.exe')) {
    if (Test-Path 'C:\xampp') { throw 'Existing incomplete/custom C:\xampp found; refusing to overwrite it' }
    $file=Join-Path $root 'xampp-8.2.12.exe'
    # Apache Friends distribution; hash from microsoft/winget-pkgs ApacheFriends.Xampp.8.2.
    Fetch-Pinned 'https://sourceforge.net/projects/xampp/files/XAMPP%20Windows/8.2.12/xampp-windows-x64-8.2.12-0-VS16-installer.exe/download' $file '12E818CE5AEC79FE646606DF3A80B35DA865EC0213646AD7C92044DCFCEC7535'
    Install-Wait $file @('--mode','unattended','--unattendedmodeui','none','--prefix','C:\xampp') 600
    # Only configure the newly provisioned bundle. Never overwrite an existing user's config.
    foreach ($cfg in @('C:\xampp\apache\conf\httpd.conf','C:\xampp\apache\conf\extra\httpd-ssl.conf')) {
      $text=Get-Content $cfg -Raw
      $text=$text -replace '(?m)^Listen\s+80\s*$','Listen 127.0.0.1:80' -replace '(?m)^Listen\s+443\s*$','Listen 127.0.0.1:443'
      Set-Content $cfg $text -Encoding ascii
    }
    $my='C:\xampp\mysql\bin\my.ini'
    $text=Get-Content $my -Raw
    $text=$text -replace '(?m)^\[mysqld\]\s*$',"[mysqld]`r`nbind-address=127.0.0.1"
    Set-Content $my $text -Encoding ascii
  }
  foreach ($file in @('C:\xampp\xampp-control.exe','C:\xampp\apache\bin\httpd.exe','C:\xampp\php\php.exe','C:\xampp\mysql\bin\mysqld.exe')) {
    if (-not (Test-Path $file)) { throw "XAMPP file missing: $file" }
  }
  Check-Command 'C:\xampp\php\php.exe' @('-v')
  Check-Command 'C:\xampp\apache\bin\httpd.exe' @('-t')
  Check-Command 'C:\xampp\mysql\bin\mysqld.exe' @('--version')
  $report.xampp='verified_files_php_apache_config_mariadb_version; services not started'
} catch { $report.xampp='failed';$report.errors+="XAMPP: $($_.Exception.Message)" }
try {
  foreach ($protocol in @('TCP','UDP')) {
    $name="RdpFree-TestHost-7777-$protocol"
    Get-NetFirewallRule -Name $name -ErrorAction SilentlyContinue | Remove-NetFirewallRule
    New-NetFirewallRule -Name $name -DisplayName "RdpFree test host $protocol 7777" -Direction Inbound -Action Allow -Protocol $protocol -LocalPort 7777 -Profile Any | Out-Null
    $rule=Get-NetFirewallRule -Name $name
    $port=$rule | Get-NetFirewallPortFilter
    if ($rule.Enabled -ne 'True' -or $rule.Action -ne 'Allow' -or $port.LocalPort -ne '7777' -or "$($port.Protocol)" -notin @($protocol,$(if($protocol -eq 'TCP'){'6'}else{'17'}))) { throw "Firewall verification failed: $protocol" }
  }
  $report.firewall7777='verified_TCP_UDP_inbound_rules; not_public_forwarding'
} catch { $report.firewall7777='failed';$report.errors+="Firewall: $($_.Exception.Message)" }
$report | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $root 'report.json') -Encoding utf8
Update-Status @{host_tools=$report} | Out-Null
foreach ($key in @('winrar','vcredist','xampp','firewall7777')) { Log "$key = $($report[$key])" }
Log 'Port 7777 is not a public relay. Use the Tailscale IP and permitted tailnet ACLs; a server must actually listen on 7777.'
if ($report.errors.Count) { throw ($report.errors -join '; ') }
