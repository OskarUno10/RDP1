# KallAncrit — Explorer preferences. No Explorer termination or RDP disconnect.
param([switch]$CurrentUserOnly)
$ErrorActionPreference = 'Stop'
$preferences = @(
  @{ Key='Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Values=@{ Hidden=1; HideFileExt=0; AutoCheckSelect=1; ShowSuperHidden=0 } },
  @{ Key='Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'; Values=@{ AppsUseLightTheme=0; SystemUsesLightTheme=0; EnableTransparency=0 } }
)
$roots = @('Registry::HKEY_CURRENT_USER')
$loadedDefault = $false
try {
  if (-not $CurrentUserOnly) {
    & reg.exe load 'HKU\RdpFreeExplorerDefault' "$env:SystemDrive\Users\Default\NTUSER.DAT" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Could not load Default profile preferences; no success reported.' }
    $loadedDefault = $true
    $roots += 'Registry::HKEY_USERS\RdpFreeExplorerDefault'
  }
  foreach ($root in $roots) {
    foreach ($group in $preferences) {
      $key = "$root\$($group.Key)"
      New-Item -Path $key -Force | Out-Null
      foreach ($entry in $group.Values.GetEnumerator()) {
        New-ItemProperty -Path $key -Name $entry.Key -Value $entry.Value -PropertyType DWord -Force | Out-Null
        if ((Get-ItemPropertyValue -Path $key -Name $entry.Key) -ne $entry.Value) { throw "Verification failed: $($entry.Key)" }
      }
    }
  }
  Write-Host 'Verified: hidden items ON, file extensions ON, item checkboxes ON, dark theme ON.'
  Write-Host 'Protected operating-system files remain hidden. Close/reopen Explorer to refresh; some theme elements may require a later sign-in. No restart is forced.'
} finally {
  if ($loadedDefault) {
    [GC]::Collect(); [GC]::WaitForPendingFinalizers()
    & reg.exe unload 'HKU\RdpFreeExplorerDefault' | Out-Null
    if ($LASTEXITCODE -ne 0) { Write-Warning 'Default profile hive could not be unloaded.' }
  }
}
