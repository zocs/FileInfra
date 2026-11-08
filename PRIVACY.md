# Privacy Policy for FileInfra

Last updated: 2026-11-09

## Overview

FileInfra shares files and clipboard text directly with devices that can reach the services you start. It does not send that content to a FileInfra backend, analytics provider or advertising service. It stores settings and access logs locally as described below.

## Data Collection

**FileInfra does not send the following to its developer or a tracking service:**
- Personal information
- Usage analytics
- Crash reports
- Device identifiers
- Location data
- Contacts or calendar data

## How FileInfra Works

- FileInfra runs a local HTTP file server (dufs) on your device
- Files are sent directly to peers on your LAN or through the network/VPN you configure
- A separate tools service shares clipboard text and generates QR codes locally
- QR contents are not sent to an external QR service
- FileInfra does not operate a cloud relay; any VPN/relay service you choose has its own privacy policy

## Local Storage and Clipboard

- App settings include selected paths, ports, permissions, addresses, language and appearance. They are stored in the platform's app preferences.
- Password credentials use platform secure storage when available. Older credentials in preferences are migrated after a successful secure-storage write; a missing desktop keyring may prevent credentials from persisting.
- Local access logs may include peer IP addresses, request paths/file names, timestamps and response statuses. They are used by the transfer-log view and troubleshooting, and are not uploaded by FileInfra.
- Shared clipboard text is held in app memory while the tools service runs and is cleared when it stops. Connected devices may retain text they already received or copied.
- Sending the device clipboard is an explicit action. On Android, the notification opens and focuses FileInfra before reading once. Pulling shared text writes the system clipboard, which remains subject to the operating system's clipboard retention rules.

## Permissions

- **Storage/Files**: Required to select and share directories on your device
- **Internet/Network**: Required to run the local HTTP server for file sharing
- **Network State**: Required to detect local IP address for QR code generation
- **Notifications / Foreground Service**: Android's persistent file-sharing notification and start/stop controls
- **Clipboard**: Explicit send/copy/pull actions; FileInfra does not continuously monitor the device clipboard

## Third-Party Services

FileInfra uses the following open-source components:
- [dufs](https://github.com/sigoden/dufs) (MIT License) - static file server

No third-party analytics, advertising, or tracking services are used.

## Data Security

- Services are reachable through the network interfaces they bind to; the file server normally binds to all interfaces (`0.0.0.0`). Firewall, router and VPN settings determine who can connect.
- The app currently uses HTTP. File and clipboard content is unencrypted unless protected by your network or VPN.
- Optional username/password authentication protects the file server. It does not protect the separate clipboard/tools service.
- The tools API checks browser Origins, but these checks do not authenticate devices or native clients. Anyone who can reach that service may read or replace shared clipboard text.
- You choose the file/directory and operation permissions, and can stop sharing at any time.

## Children's Privacy

FileInfra does not knowingly collect any information from children under 13.

## Changes to This Policy

Any changes to this privacy policy will be reflected in the app and on this page.

## Contact

For questions about this privacy policy, contact: zocs@live.com
