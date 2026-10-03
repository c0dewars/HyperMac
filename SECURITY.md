# Security policy

HyperMac is currently a development preview, not a production release. It uses macOS Accessibility permission to inspect and move application windows. Configuration can contain application identifiers and window-title matching rules; review diagnostics before sharing them.

Do not post credentials, private window titles, signing keys, or personal configuration in issues. Report security concerns privately to the repository owner through an established private channel. No production version or security-response SLA is currently offered.

Private signing keys stay in the local Keychain. CI builds are ad-hoc signed test artifacts, not notarized releases. Public releases must pass Developer ID signing, notarization, Gatekeeper and clean-Mac installation validation.
