# KallAncrit — optional CPU-renderer toolkit, NOT a physical GPU or FPS upgrade.
# Keep Mesa files isolated: never overwrite Windows DLLs or force software rendering globally.
$XyTag = 'XyRDP:grafis'
. "$PSScriptRoot/lib-common.ps1"
$root = 'C:\XyRDP\grafis'
New-Item -ItemType Directory -Force -Path $root | Out-Null
$adapters = @(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | ForEach-Object { $_.Name }) -join ' | '
try {
  $asset = Get-GhAssetUrl 'pal1000/mesa-dist-win' 'mesa3d-.*-release-msvc\.7z$'
  if (-not $asset) { throw 'Mesa release asset unavailable' }
  $archive = Join-Path $root $asset.name
  if (-not (Get-File $asset.url $archive 300)) { throw 'Mesa download failed' }
  $seven = Get-Command 7z.exe -ErrorAction SilentlyContinue
  $sevenPath = if ($seven) { $seven.Source } else { "$env:ProgramFiles\7-Zip\7z.exe" }
  if (-not (Test-Path $sevenPath)) { throw '7-Zip unavailable' }
  $destination = Join-Path $root ('mesa-' + ($asset.tag -replace '[^a-zA-Z0-9._-]', '_'))
  & $sevenPath x $archive "-o$destination" -y 2>&1 | Out-Null
  if ($LASTEXITCODE -ne 0) { throw 'Mesa extraction failed' }
  $dlls = @(Get-ChildItem $destination -Recurse -Filter opengl32.dll -File -ErrorAction Stop)
  if (-not $dlls.Count) { throw 'Mesa OpenGL files missing from extracted release' }
  @"
Optional Mesa CPU renderer toolkit: $destination
Windows graphics drivers and DLLs were not changed.
Keep each architecture and its dependencies together; x86 applications need x86 libraries.
No global environment override is installed. Do not copy DLLs into System32/SysWOW64.
Use the package's upstream per-application deployment instructions only for an application that needs Mesa.
Mesa OpenGL/Vulkan support is not a Direct3D 9 fix for GTA SA.
WARP is provided by Windows for supported Direct3D uses; it does not create a hardware GPU.
CPU rendering may be slower, and game compatibility/performance has NOT been validated.
This script does not restore DLLs modified by older scripts on existing sessions.
"@ | Set-Content (Join-Path $root 'README.txt') -Encoding utf8
  Log "Mesa toolkit staged at $destination; NOT activated globally. No FPS gain claimed."
  Update-Status @{ grafis = @{ mode='toolkit_only'; mesa=$asset.tag; adapters=$adapters; note='Optional isolated CPU renderer files; not activated or benchmarked.' } } | Out-Null
} catch {
  Log "Graphics toolkit unavailable: $($_.Exception.Message)"
  Update-Status @{ grafis = @{ mode='gagal'; adapters=$adapters; note='Toolkit staging failed; native Windows graphics unchanged.' } } | Out-Null
}
