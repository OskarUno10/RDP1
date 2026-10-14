# Portmap access (workflow schema 5)

Credit: KallAncrit. Updated 2026-10-12.

OpenVPN runs on the Windows runner only. Clients use the public mapping hostname and allocated TCP port with an RDP client. This is public RDP exposure, not a private tailnet.

## Per-repository setup

1. Each owner creates their own Portmap configuration and TCP mapping to local Windows port 3389.
2. Store the entire inline OpenVPN configuration as Actions Secret `PORTMAP_OVPN_CONFIG`. Never commit it, print it or copy the owner's configuration to other people's forks.
3. Set `RDP_PASSWORD` separately. Use a strong unique password and save the optional encrypted dashboard copy if password reveal is needed.
4. Dashboard Settings: `akses=portmap`, `portmap_host` and `portmap_port`. Secrets required by Setup depend on the selected access mode.
5. Manual Actions dispatch accepts the same inputs. Repo variables `PORTMAP_HOST`/`PORTMAP_PORT` are fallback values when the manual inputs are blank. Variables/secrets are not an automatic fork onboarding mechanism.
6. Authorize the target repository in the GitHub App installation and select it in dashboard Connection.

## Security and behavior

The .ovpn profile is validated against supported directives, requires inline CA/client certificate/key plus server-certificate verification, and disallows executable hooks. Local config directory ACL is limited to SYSTEM and Administrators. OpenVPN is downloaded from the official stable distribution and its Authenticode publisher/signature checked. Route pulling is disabled to avoid changing the runner's default route; the process must report Initialization Sequence Completed before proceeding. RDP requires an existing listener; NLA/TLS are enforced and a TCP 3389 firewall rule is scoped to an active OpenVPN adapter. Finalization stops only the recorded OpenVPN executable, removes the local private configuration and the dedicated firewall rule. Logs never intentionally print the configuration or password.

Portmap connection status means the VPN and local listener were prepared. It does not prove public ingress, actual RDP client compatibility, sound/microphone or latency. Provider account limits, mapping correctness and Allowed IPs must still permit the user.

## This owner's setup and tests

- Applied only to `xykal/XyRDP`, as explicitly selected. Configuration is stored as a sealed GitHub Actions Secret, not in Git.
- Public mapping: `kallxycrigi-41858.portmap.host:41858` -> Windows TCP 3389.
- Existing RDP password retained; no passwords printed.
- Real handshake-only validation `38266310125` succeeded on Windows Server 2022; it did not open public RDP, then disconnected and removed the private local config.
- Live admin Setup reports compatible/ready with provider portmap and no missing secrets.
- Attempt to select XyRDP through the user's GitHub App was rejected by GitHub with 422: the parent installation lacks access to XyRDP. Existing selected repo remains unchanged. Owner must add XyRDP through GitHub installed-app settings, then select it in the dashboard. No permission restriction was bypassed.
- 21 web tests passed, including hostname/port status validation and stale-session rejection. Full phone RDP login has not been verified.

## Community join and domains

A join-channel/group link can be part of onboarding, but clicking it is not verified membership and cannot make repository secrets inherit across forks. Never distribute one user's Portmap private key to other fork owners.

Portmap's managed custom-domain feature is advertised in its paid plan. A plain DNS-only hostname alias is a separate DNS mechanism: it does not remove the allocated port, provision an RDP certificate, provide proxying, or reduce latency. No domain record was changed in this setup.

## 2026-10-12: default provider and DNS test

Tailscale remains the default in workflow_dispatch and dashboard defaults. Owner XyRDP saved settings have been explicitly restored to Tailscale; the Portmap configuration is retained. Settings checks the Portmap secret metadata without reading its value. The Portmap dropdown option is disabled unless the secret exists and a valid hostname/port are present. Unknown secret-check status fails closed for Portmap without hiding Tailscale. Settings PUT independently rejects incomplete Portmap configuration; dispatch still verifies provider secrets.

Created only the previously unused DNS-only CNAME rdp.projectkal.my.id to kallxycrigi-41858.portmap.host, TTL 300. Both names resolved to the same address from the test resolver. Port 41858 remains necessary. Owner stored settings and the PORTMAP_HOST repository variable use this alias. This verifies DNS resolution only, not an end-to-end RDP login, provider policy, certificate identity, or latency. No session was started or stopped in this update.

Validation: 23 unit tests, production API default save and invalid Portmap rejection, mobile browser gated-dropdown scenarios with metadata mocked. Existing GitHub App installation access remains a separate requirement.
