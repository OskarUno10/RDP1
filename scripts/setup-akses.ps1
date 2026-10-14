# RdpFree: private Tailscale access only. Credit: KallAncrit.
param([switch]$InstallOnly)
$XyTag = 'RdpFree:access'
. "$PSScriptRoot/lib-common.ps1"
$ErrorActionPreference = 'Stop'
$work = 'C:\ProgramData\RdpFree\access'
New-Item -ItemType Directory -Path $work -Force | Out-Null
function Run-Bounded([string]$File, [string[]]$ArgsList, [int]$Seconds=90) {
  $out = Join-Path $work ([guid]::NewGuid().ToString('N')+'.out')
  $err = "$out.err"
  try {
    $p = Start-Process -FilePath $File -ArgumentList $ArgsList -PassThru -NoNewWindow -RedirectStandardOutput $out -RedirectStandardError $err
    if (-not $p.WaitForExit($Seconds * 1000)) { $p | Stop-Process -Force -ErrorAction SilentlyContinue; throw 'Perintah Tailscale melewati timeout' }
    $p.WaitForExit()
    return @{ code=$p.ExitCode; text=(Get-Content $out -Raw -ErrorAction SilentlyContinue); error=(Get-Content $err -Raw -ErrorAction SilentlyContinue) }
  } finally { Remove-Item $out,$err -Force -ErrorAction SilentlyContinue }
}
try {
  if (-not $InstallOnly -and -not $env:TAILSCALE_AUTH_KEY) { throw 'Isi secret TAILSCALE_AUTH_KEY terlebih dahulu.' }
  $exe = "$env:ProgramFiles\Tailscale\tailscale.exe"
  if (-not (Test-Path $exe)) {
    $msi=Join-Path $work 'tailscale.msi'
    if (-not (Get-File 'https://pkgs.tailscale.com/stable/tailscale-setup-latest-amd64.msi' $msi 90)) { throw 'Unduhan Tailscale gagal' }
    $signature=Get-AuthenticodeSignature $msi
    if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'Tailscale') { throw 'Signature installer Tailscale tidak valid' }
    # Storage cleanup must preserve these directories: Windows Installer runs as SYSTEM.
    foreach ($dir in @("$env:SystemRoot\Temp", $env:TEMP, $env:TMP, $env:RUNNER_TEMP)) {
      if ($dir) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    }
    $msiLog=Join-Path $work 'tailscale-install.log'
    for ($attempt=1; $attempt -le 3; $attempt++) {
      $install=Run-Bounded 'msiexec.exe' @('/i',"`"$msi`"",'/qn','/norestart','/L*v',"`"$msiLog`"") 240
      if ($install.code -ne 1618 -or $attempt -eq 3) { break }
      Log 'Windows Installer sedang sibuk; mencoba lagi dalam 15 detik.'
      Start-Sleep -Seconds 15
    }
    Log "Installer Tailscale selesai: exit $($install.code)"
    if ($install.code -notin @(0,3010)) {
      # Emit selected installer diagnostics only. Never upload the full environment/log.
      Get-Content $msiLog -ErrorAction SilentlyContinue | Where-Object { $_ -match 'Return value 3|error [0-9]{3,}|Installation success or error status|Product:.*--' } | Select-Object -Last 15 | ForEach-Object {
        $line="$_"
        Get-ChildItem Env: | Where-Object { $_.Name -match 'TOKEN|PASSWORD|SECRET|KEY' -and $_.Value.Length -ge 4 } | ForEach-Object { $line=$line.Replace($_.Value,'[redacted]') }
        Log $line
      }
    }
    if ($install.code -notin @(0,3010)) { throw "Installer Tailscale gagal, exit $($install.code)" }
  }
  if (-not (Test-Path $exe)) { throw 'Tailscale CLI tidak ditemukan' }
  Start-Service Tailscale -ErrorAction Stop
  if ($InstallOnly) { $version=Run-Bounded $exe @('version') 30; if ($version.code -ne 0) { throw 'Verifikasi CLI Tailscale gagal' }; Log "Install-only validation OK: $($version.text.Trim())"; return }
  $hostName=("$env:HOSTNAME-$env:GITHUB_RUN_NUMBER" -replace '[^a-zA-Z0-9-]','').Trim('-')
  if (-not $hostName) { $hostName='rdpfree' }; if ($hostName.Length -gt 60) { $hostName=$hostName.Substring(0,60) }
  $up=Run-Bounded $exe @('up',"--auth-key=$env:TAILSCALE_AUTH_KEY","--hostname=$hostName",'--accept-dns=false','--timeout=90s') 120
  if ($up.code -ne 0) { throw 'Tailscale menolak koneksi. Periksa masa berlaku auth key dan persetujuan perangkat di tailnet.' }
  $state=Run-Bounded $exe @('status','--json') 30
  $status=$state.text | ConvertFrom-Json
  $ip=@($status.Self.TailscaleIPs | Where-Object { $_ -match '^100\.' }) | Select-Object -First 1
  if ($status.BackendState -ne 'Running' -or -not $ip) { throw 'Tailscale belum siap atau belum disetujui oleh pemilik tailnet' }
  $deadline=(Get-Date).AddSeconds(90)
  do {
    $listener=Get-NetTCPConnection -LocalPort 3389 -State Listen -ErrorAction SilentlyContinue
    if ($listener) { break }; Start-Sleep -Seconds 3
  } while ((Get-Date) -lt $deadline)
  if (-not $listener) { throw 'Tailscale tersambung tetapi listener RDP 3389 belum aktif; periksa setup-rdp.' }
  # Restrict known RDP rules to the private tailnet address space.
  Get-NetFirewallRule -Name 'RemoteDesktop-*' -ErrorAction SilentlyContinue | Set-NetFirewallRule -RemoteAddress '100.64.0.0/10' -ErrorAction SilentlyContinue
  Get-NetFirewallRule -DisplayName 'XyDesk Remote*' -ErrorAction SilentlyContinue | Set-NetFirewallRule -RemoteAddress '100.64.0.0/10' -ErrorAction SilentlyContinue
  Update-Status @{ akses=@{mode='tailscale';tailscale=@{status='ok';ip="$ip";magicdns="$($status.Self.DNSName)";hostname=$hostName;note='HP/PC harus login Tailscale pada tailnet yang sama. TCP 3389 harus diizinkan ACL.'}} } | Out-Null
  Log "Tailscale siap: $ip`:3389. Tidak ada akses publik."
} catch {
  Update-Status @{ akses=@{mode='tailscale';tailscale=@{status='failed';note=$_.Exception.Message}} } | Out-Null
  throw
}
