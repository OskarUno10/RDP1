# RdpFree Relay · Windows local panel

KallAncrit. TCP relay with local authenticated browser control. Not a NAT bypass,
not a VPN installer, not a public hosting guarantee. UDP/SA-MP is out of scope.

## Windows packaged application
Extract the whole ZIP. Double-click `RdpFreeRelay.exe`. Keep its console open;
it opens a browser at `http://127.0.0.1:8787` using a private per-launch token.
Do NOT expose port 8787, share the token, or disable antivirus. The binary is not
code-signed; review the source/build provenance if Windows shows a warning.

Python source alternative: install Python 3.11+ from python.org and run
`py -3 relay_panel.py`. No third-party Python runtime dependencies.

1. Install/authorize Tailscale on both purchased RDP and runner (separately).
2. Create session: runner Tailscale IPv4, destination 3389, relay port e.g. 7778.
3. Start it. "Listening" proves local binding ONLY, not public reachability.
4. Use the panel's firewall command if needed, in elevated PowerShell. Rules are
   explicitly user-managed, not automatically deleted. Login 5151/3389 is reserved.
5. Seller must map a public TCP port to this machine's relay port. This application
   cannot modify seller NAT. For the known RDP 163.52.135.2:5151 / 192.168.5.151,
   that additional mapping remains unverified. Do not take over port 5151.
6. Only after external verification, point DNS-only relay.projectkal.my.id at the
   public relay IP and connect with its PUBLIC forwarded port (may differ locally).

## Session behavior and limits
- Maximum 360 minutes from session creation. Reconnect, stop/start, app restart
  do not extend expiry. Active connection sockets close on timeout or manual stop.
- Stored sessions load STOPPED after app restart; expired ones cannot resume.
- Manual session clock, NOT synchronized to GitHub run start/end. No automatic
  action on GitHub cancellation; stop it yourself if the runner ends early.
- A new manually created session gets a new timer; not an account-wide six-hour quota.
- Closing/crashing the application closes its sockets. Not a Windows service;
  sleep/reboot/outage interrupts relay. At most eight listeners, 32 clients each.
- TCP byte forwarding; no payload inspection/logging. No passwords stored. This
  relay itself adds no encryption. Use Tailscale/WireGuard to targets and TLS/NLA
  on RDP. Only private/Tailscale IPv4 targets accepted. It does not bypass ACLs.
- Browser panel binds ONLY 127.0.0.1, rejects other Host/Origin values, requires a
  random bearer token on API routes. Local OS account security remains necessary.
- Config: %LOCALAPPDATA%\RdpFreeRelay\sessions.json; activity log kept in memory.
- Firewall rules, actual Tailscale connection, DNS and seller NAT remain external
  prerequisites. Interface status deliberately never claims internet readiness.

## Development
`python -m unittest discover -s tests -v`
`python -m PyInstaller --clean --noconfirm --onefile --name RdpFreeRelay --add-data "panel.html;." relay_panel.py` (Windows).
