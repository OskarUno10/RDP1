# Desktop maintenance — 2026-10-13

- Retired TranslucentTB download/install/startup provisioning. Legacy configuration
  values are ignored; new sessions use native opaque taskbar settings. This does
  not remotely uninstall software from an already-running RDP session.
- Lightshot enabled in template config. Use official vendor installer, verify
  pinned SHA256 from microsoft/winget-pkgs (Skillbrains.Lightshot 5.5.0.7), request all-users install, enforce a
  180-second installer wait, check exit code and actual executable. Startup paths
  are quoted. Remove unnecessary inbound firewall permission and unverified mirror.
- Mesa remains optional, now staged as an isolated toolkit with upstream files.
  Never overwrite System32, change system-DLL ownership, or force software OpenGL/
  Vulkan globally. This is not a physical GPU, a D3D9 game fix, or a measured FPS
  improvement. Previous system-wide modifications in existing sessions are not
  automatically reverted. Read C:\XyRDP\grafis\README.txt before per-app setup.
- RDP password masking is unchanged. Temporary sessions do not make durable
  public workflow logs private. Credentials remain in the protected dashboard.
- Initial Windows test rejected the unpinned vendor download at signature validation.
  Changed to the versioned vendor URL and independently published winget SHA256;
  mismatched files fail closed rather than bypassing integrity checks.
- Added manual Windows-2022 validation for parsing and repeat Lightshot installation;
  it does not start an RDP session or install games.

Validation result: Windows-2022 run 38359540094 (https://github.com/xykal/XyRDP/actions/runs/38359540094)
passed script parsing, disabled legacy transparency config, vendor Lightshot
installation, executable discovery, and repeat installation. Interactive screenshot
capture under xyadmin and Mesa performance have not been tested. No RDP session
was started/stopped.

## Explorer defaults
`setup-explorer.ps1` runs independently of optional extras before the connection
summary: hidden items, extensions, item checkboxes and dark theme are enabled.
Protected OS files stay hidden. Values are verified in HKCU and the Default user
hive (inherited on first sign-in). No shell is killed and no logout is forced.
Existing interactive sessions can run the standalone script with `-CurrentUserOnly`;
existing offline user profiles are not modified. Legacy Windows dialogs may not
support dark theme.

Windows-2022 validation run 38360918910 passed: PowerShell parsing, Explorer registry read-back, repeated application, and Lightshot install/reinstall. Visual dark-theme coverage of all Windows dialogs was not tested.
