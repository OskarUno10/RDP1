# RdpFree / KallAncrit. OpenVPN client lives on Windows, not on the user's phone.
param([switch]$ValidateOnly)
$XyTag='RdpFree:portmap'
. "$PSScriptRoot/lib-common.ps1"
$ErrorActionPreference='Stop'
$root='C:\ProgramData\RdpFree\portmap'
New-Item -ItemType Directory -Path $root -Force | Out-Null
& icacls.exe $root /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' | Out-Null
$config=Join-Path $root 'client.ovpn';$logFile=Join-Path $root 'openvpn.log'
try {
  if(-not $env:PORTMAP_OVPN_CONFIG){throw 'Secret PORTMAP_OVPN_CONFIG belum diisi.'}
  $hostName=$env:PORTMAP_HOST;$port=0
  if($hostName -notmatch '^(?=.{1,253}$)(?:[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,63}$' -or -not [int]::TryParse($env:PORTMAP_PORT,[ref]$port) -or $port -lt 1 -or $port -gt 65535){throw 'Isi hostname dan port publik Portmap dengan benar.'}
  # Reject executable hooks, extra files and tunnel settings outside the supported profile.
  $allowed=@('client','nobind','dev','proto','remote','remote-cert-tls','key-direction','cipher','auth','resolv-retry','persist-key','persist-tun','verb','mute','explicit-exit-notify','sndbuf','rcvbuf','keepalive','tun-mtu','mssfix','tls-version-min','verify-x509-name')
  $block='';$seen=@{}
  foreach($raw in ($env:PORTMAP_OVPN_CONFIG -split "`r?`n")){
    $line=$raw.Trim();if(-not $line -or $line.StartsWith('#') -or $line.StartsWith(';')){continue}
    if($block){if($line -eq "</$block>"){$block=''};continue}
    if($line -match '^<(ca|cert|key|tls-auth|tls-crypt)>$'){$block=$Matches[1];$seen[$block]=$true;continue}
    $directive=($line -split '\s+')[0]
    if($directive -notin $allowed){throw 'Profil OpenVPN memiliki directive yang belum didukung. Konfigurasi tidak dijalankan.'}
    if($directive -eq 'dev' -and $line -notmatch '^dev\s+tun$'){throw 'Gunakan konfigurasi OpenVPN TUN.'}
  }
  if($block -or -not $seen.ca -or -not $seen.cert -or -not $seen.key){throw 'Profil harus memiliki CA, certificate dan private key inline lengkap.'}
  if($env:PORTMAP_OVPN_CONFIG -notmatch '(?m)^\s*remote-cert-tls\s+server\s*$'){throw 'Profil harus memverifikasi certificate server.'}
  [IO.File]::WriteAllText($config,$env:PORTMAP_OVPN_CONFIG)
  $env:PORTMAP_OVPN_CONFIG=''
  $exe="$env:ProgramFiles\OpenVPN\bin\openvpn.exe"
  if(-not(Test-Path $exe)){
    foreach($dir in @("$env:SystemRoot\Temp",$env:TEMP,$env:TMP)){if($dir){New-Item -ItemType Directory -Path $dir -Force | Out-Null}}
    $msi=Join-Path $root 'openvpn.msi'
    if(-not(Get-File 'https://build.openvpn.net/downloads/releases/latest/openvpn-latest-stable-amd64.msi' $msi 120)){throw 'Unduhan OpenVPN resmi gagal.'}
    $sig=Get-AuthenticodeSignature $msi
    if($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch 'OpenVPN'){throw 'Signature installer OpenVPN tidak valid.'}
    $p=Start-Process msiexec.exe -ArgumentList @('/i',"`"$msi`"",'/qn','/norestart') -PassThru
    if(-not $p.WaitForExit(240000)){$p | Stop-Process -Force -ErrorAction SilentlyContinue;throw 'Installer OpenVPN timeout.'};$p.WaitForExit()
    if($p.ExitCode -notin @(0,3010)){throw "Installer OpenVPN gagal, kode $($p.ExitCode)."}
  }
  if(-not(Test-Path $exe)){throw 'OpenVPN executable tidak ditemukan.'}
  Remove-Item $logFile -Force -ErrorAction SilentlyContinue
  $proc=Start-Process $exe -ArgumentList @('--config',"`"$config`"",'--log',"`"$logFile`"",'--verb','3','--route-nopull','--script-security','1','--disable-dco','--data-ciphers','AES-256-GCM:AES-128-GCM:AES-128-CBC:AES-256-CBC','--auth-nocache') -PassThru -WindowStyle Hidden
  $proc.Id | Set-Content (Join-Path $root 'pid.txt')
  $deadline=(Get-Date).AddSeconds(100);$connected=$false
  do {
    Start-Sleep 2;$proc.Refresh()
    if($proc.HasExited){throw 'OpenVPN berhenti sebelum tersambung. Periksa profil, masa berlaku certificate, dan koneksi UDP/TCP.'}
    if(Test-Path $logFile){$text=Get-Content $logFile -Raw;if($text -match 'Initialization Sequence Completed'){$connected=$true;break}}
  }while((Get-Date) -lt $deadline)
  if(-not $connected){throw 'Portmap belum tersambung dalam 100 detik; log privat tersedia di folder Portmap Windows.'}
  if($ValidateOnly){Log 'VALIDASI: OpenVPN tersambung; tidak membuka RDP atau mempublikasikan session.';return}
  $adapter=Get-NetAdapter | Where-Object {$_.Status -eq 'Up' -and $_.InterfaceDescription -match 'OpenVPN|TAP-Windows|Wintun'} | Select-Object -First 1
  if(-not $adapter){throw 'Interface VPN aktif tidak ditemukan; firewall tidak dibuka.'}
  if(-not(Get-NetTCPConnection -LocalPort 3389 -State Listen -ErrorAction SilentlyContinue)){throw 'OpenVPN tersambung tetapi RDP belum mendengarkan port 3389.'}
  Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name UserAuthentication -Value 1
  Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name SecurityLayer -Value 2
  Get-NetFirewallRule -Name 'RemoteDesktop-*' -ErrorAction SilentlyContinue | Disable-NetFirewallRule -ErrorAction SilentlyContinue
  Get-NetFirewallRule -DisplayName 'XyDesk Remote*' -ErrorAction SilentlyContinue | Disable-NetFirewallRule -ErrorAction SilentlyContinue
  Remove-NetFirewallRule -DisplayName 'RdpFree Portmap RDP' -ErrorAction SilentlyContinue
  New-NetFirewallRule -DisplayName 'RdpFree Portmap RDP' -Direction Inbound -Action Allow -Protocol TCP -LocalPort 3389 -InterfaceAlias $adapter.Name -Profile Any | Out-Null
  Update-Status @{akses=@{mode='portmap';portmap=@{status='ok';host=$hostName;port=$port;note='OpenVPN dan listener RDP siap. Endpoint publik; koneksi dari HP masih perlu diuji.'}}} | Out-Null
  Log "Portmap siap di runner: $hostName`:$port -> TCP 3389. NLA dan TLS aktif; password tidak dicetak."
}catch{
  Update-Status @{akses=@{mode='portmap';portmap=@{status='failed';note=$_.Exception.Message}}} | Out-Null
  throw
}
