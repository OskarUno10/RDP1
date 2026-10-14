# RdpFree: disconnect only its Tailscale session, never kill unrelated SSH processes.
$XyTag='RdpFree:finalize'
. "$PSScriptRoot/lib-common.ps1"
$exe="$env:ProgramFiles\Tailscale\tailscale.exe"
if (Test-Path $exe) {
  try { & $exe down 2>$null | Out-Null; & $exe logout 2>$null | Out-Null } catch { Log 'Tailscale perlu diperiksa pemilik tailnet' }
}
Log 'Sesi dihentikan. Mesin self-hosted tidak dihapus otomatis.'

$portmapRoot='C:\ProgramData\RdpFree\portmap'
$pidFile=Join-Path $portmapRoot 'pid.txt'
if(Test-Path $pidFile){
  $pidValue=0
  if([int]::TryParse((Get-Content $pidFile -Raw).Trim(),[ref]$pidValue)){
    $process=Get-Process -Id $pidValue -ErrorAction SilentlyContinue
    if($process -and $process.Path -eq "$env:ProgramFiles\OpenVPN\bin\openvpn.exe"){$process | Stop-Process -Force -ErrorAction SilentlyContinue}
  }
}
Remove-Item (Join-Path $portmapRoot 'client.ovpn'),$pidFile -Force -ErrorAction SilentlyContinue
Remove-NetFirewallRule -DisplayName 'RdpFree Portmap RDP' -ErrorAction SilentlyContinue
Log 'Tunnel Portmap sesi ini ditutup; konfigurasi privat lokal dibersihkan.'
