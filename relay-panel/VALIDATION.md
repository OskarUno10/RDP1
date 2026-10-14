# Validation — 2026-10-13

Source/build commit: 2c68b92.
Windows Server 2022 run: https://github.com/xykal/XyRDP/actions/runs/38427925294

Passed six tests on Linux and Windows: actual bidirectional TCP echo forwarding,
manual stop closes active socket, expiry closes active socket and prevents restart,
saved timer survives app restart without extension, reserved ports/invalid targets
and durations rejected, duplicate bind fails without a false success status, and
API authorization/Host/Origin/body checks. Some checks share one test case.

PyInstaller packaged EXE started and served the local HTML panel in Windows CI.
EXE SHA256 (verified after downloading artifact):
765b1b6f255ecaf7b8cec4dd0b0ec15dc4ae7f9906dd76d48885994dbeb9c379

No interactive RDP login, seller-NAT traversal, public port mapping, actual
Tailscale path, domain DNS changes or Windows desktop visual interaction has been
verified. This release is a manual TCP relay controller, not a GitHub-integrated
session broker. The executable is unsigned. No new RDP session was started or
stopped to perform validation.
