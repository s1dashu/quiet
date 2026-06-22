# Security Policy

## Reporting a Vulnerability

Please report security issues privately by opening a GitHub security advisory on the repository, or by contacting the maintainer through the repository owner profile.

Do not include sensitive personal files, API keys, or private logs in public issues.

## Supported Versions

Security fixes target the latest version on `main` until public releases are formalized.

## Local Data and API Keys

Blackhole stores runtime data under `~/.blackhole` and user-visible files under `~/Documents/Blackhole`. API keys are configured locally in the app settings, stored in the macOS Keychain, and should never be committed to the repository.

When using a remote model provider, model requests are sent to the configured provider. Quiet does not operate a hosted backend for file storage or telemetry.
