# Security policy

## Reporting a vulnerability

Please report security issues **privately**, not in public issues. Use GitHub's private
vulnerability reporting (Security → Report a vulnerability) or email
`security@opendisplay.example` *(placeholder — replace before public launch)*.

We aim to acknowledge reports promptly, work on a fix under coordinated disclosure, and
credit reporters who wish to be named. Supported-version and disclosure-timeline details
will be finalized before the first public release.

## Scope & threat model (summary)

OpenDisplay reasons about these primary threats (PRD §14.1):

| Threat | Control |
|--------|---------|
| Malicious local automation request | Authenticated gateway, loopback default, non-bypassable safety checks, rate limits, audit log |
| Compromised provider/dependency | Minimal dependencies, provider isolation, SBOM, review, signing |
| Leaked display/network identifiers | Local-only storage; hash/redact on export; no analytics by default |
| Capture without clear consent | On-demand permission, active indicator, stop on lock/logout |
| Update incompatibility (black screen / startup loop) | Signed updates, OS compatibility flags, safe-mode migration, experimental defaults off |
| Corrupt settings/import | Schema validation, atomic writes, backups, quarantine, recovery-first startup |
| Stolen API token | Keychain, scoped/rotatable token, LAN off by default, audit & revoke |
| Supply-chain tampering | Protected branches, reproducible metadata, checksums, notarization, provenance/SBOM |

## Privacy defaults

No analytics, crash upload, network discovery, HTTP listener, screen capture, or LAN access
on a fresh install. Diagnostics are opt-in and previewable. Display serials, EDID, and
network identifiers are treated as potentially identifying; logs use pseudonymous IDs and
secrets live only in the Keychain — never in exported settings or support bundles.

## Secure development

Threat model and security review are required for the lifecycle provider, rescue IPC, update
channel, and local API before 1.0. Dependencies are pinned and scanned; high/critical
findings block release.
