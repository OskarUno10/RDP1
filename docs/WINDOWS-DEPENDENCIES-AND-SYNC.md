# Windows, dependencies and dashboard synchronization

Credit: KallAncrit · Updated 2026-10-11

## What actually changed

- Workflow schema 4 matches dashboard input names and allowed choices.
- Standard x64 images: `windows-2022`, `windows-2025`, `windows-latest`. These are Windows Server images, not renamed Windows 7/10/11 desktops.
- No self-hosted selection is required in the dashboard. Existing saved legacy runner labels migrate to `windows-2022`; saving does not start a job.
- Connection setup, original XyVerse wallpaper and status publication precede optional downloads/debloat. Fast defaults skip storage boost, theme changes, Mesa and desktop extras. Queue time and download latency are not guaranteed.
- RAM/CPU are allocated by GitHub, not selectable upgrades. Actual CPU threads/RAM/free C: disk at setup are reported for new sessions. Storage cleanup does not enlarge the disk.
- `setup-samp.ps1` now installs/verifies dependencies only: official signed Microsoft June 2010 DirectX, VC++ x86/x64 and VC++ 2013 x86. DirectPlay/.NET 3.5 report their actual feature state or unavailable/source-required; failures are not relabeled successful.
- Both System32 and SysWOW64 are checked for d3dx9_25, d3dx9_43, d3dcompiler_43 and xinput1_3. A newer OS DirectX version does not imply the legacy 32-bit libraries exist.
- No GTA, SA-MP client, mods, No-CD files or license bypass are installed. Previous GTA URL/extra-mod settings are removed/ignored. Install owned game files and the appropriate client manually.
- Dependencies passing does not verify GTA rendering, joining a multiplayer server, GPU feature levels, microphone capture or Roblox gameplay. Roblox on Windows Server is reported unsupported rather than pretending DX9 fixes it. No VM/anti-cheat spoofing is supplied.

## Evidence and limits

- Live owner run `38139271663` on the old workflow skipped the SA-MP/DirectX step because it was gated on self-hosted. Its Tailscale and status publication steps succeeded. This session was not stopped or modified.
- Actions dependency validation `38153317641` passed full dependency installation and a repeated DirectX check on both Windows Server 2022 and 2025. It did not launch RDP or install/play games.
- Tailscale installer validation `38109266815` passed previously. Windows Temp directory/ACL preservation fixes an installer prerequisite that the old storage cleanup removed.
- Web dispatch contract/auth/duplicate guards are covered by automated tests. Live web readback sees actual GitHub runs and steps. A duplicate start was rejected without stopping the existing session.
- Owner's GitHub App selected `xykal/gatau`, initially on schema 2, not the main template repository. Its template-owned workflow/scripts were synced to schema 4 at `8115958`. Its **RDP_PASSWORD and TAILSCALE_AUTH_KEY are absent**: owner must fill them in dashboard Setup before a real run can start. Repository secrets cannot be read or copied back from GitHub.

## Updating an existing repository

Update `.github/workflows/rdp-6h.yml`, `scripts/`, and the original `assets/` from the template. Preserve secrets, repository permissions, unrelated user files and saved account settings. Check the dashboard Setup compatibility indicator. GitHub App has read-only source access and cannot silently upgrade another user's repository.

Existing sessions keep their checked-out old scripts. Use a new session for runtime fixes; the dashboard does not remotely patch an already-running Windows VM.

## Community statistics

A real GitHub login counts automatically, with a visible-dashboard heartbeat for presence. Total/online require no checkbox. Publishing an individual's photo/name is a separate optional control; existing opt-outs are preserved. Online means website presence within five minutes, not an active RDP session.

## VPS and browser warnings

A user-controlled VPS can host a private VPN such as WireGuard as an alternative architecture. Deployment needs its OS, root/network capabilities, UDP reachability and a chosen key-management plan; it is not configured by this update. Do not expose unauthenticated RDP publicly. Pterodactyl normally manages Linux game containers and is not a Windows VM or a replacement for KVM/Hyper-V; an ordinary container may lack TUN/NET_ADMIN capabilities.

A browser security warning requires the exact URL, browser and screenshot for diagnosis. HTTPS reachability does not prove a domain is unflagged by every security vendor. Do not bypass warnings or disable antivirus; investigate the source and request review from the relevant provider if appropriate.

## Official references

- https://docs.github.com/en/actions/reference/runners/github-hosted-runners
- https://www.microsoft.com/en-us/download/details.aspx?id=8109
- https://en.help.roblox.com/hc/en-us/articles/203312800-Computer-Hardware-Operating-System-Requirements
