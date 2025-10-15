# DNSChanger (macOS Menu Bar DNS Changer)

A production-ready macOS menu bar application built with Swift/SwiftUI and a privileged helper via SMJobBless to change system DNS for all active network services without repeated admin prompts.

- Platforms: macOS 13 Ventura+, Intel (x86_64) and Apple Silicon (arm64)
- Tech: Swift 5, SwiftUI, NSStatusBar, NSXPCConnection, SMJobBless privileged helper
- CI/CD: GitHub Actions to build signed universal `.app`, `.pkg`, and `.dmg` artifacts, with optional notarization

This repository is structured to be built headlessly on GitHub macOS runners, producing fully distributable artifacts.


## Features

- Menu bar app (no Dock icon), profile selector with active checkmark
- Predefined and user-defined DNS profiles (persisted in UserDefaults)
- Apply DNS to all active network services
- Clear DNS to DHCP defaults
- Flush DNS cache
- Privileged helper installed once using SMJobBless (single admin prompt)
- Universal binary (arm64 + x86_64)
- CI/CD builds and optionally notarizes `.app`, `.pkg` and `.dmg`, publishes to GitHub Releases


## Repository Layout

```
dnschanger/
├─ README.md
├─ LICENSE
├─ .gitignore
├─ .github/
│  └─ workflows/
│     └─ release.yml
├─ scripts/
│  ├─ build_pkg.sh
│  ├─ build_dmg.sh
│  ├─ codesign_and_archive.sh
│  ├─ notarize.sh
│  └─ verify_signature.sh
├─ XcodeProject/
│  ├─ project.yml                 # XcodeGen spec (generates .xcodeproj/.xcworkspace)
│  ├─ DNSChanger.xcodeproj        # Generated in CI (not committed)
│  └─ DNSChanger.xcworkspace      # Generated in CI (not committed)
├─ Sources/
│  ├─ App/
│  │  ├─ DNSChangerApp.swift
│  │  ├─ AppDelegate.swift
│  │  ├─ MenuBarController.swift
│  │  ├─ DNSChangerClient.swift
│  │  ├─ Models/DNSProfile.swift
│  │  └─ Assets.xcassets/
│  ├─ Helper/
│  │  ├─ main.swift
│  │  ├─ DNSChangerHelper.swift
│  │  └─ Info.plist
│  └─ Shared/
│     └─ DNSChangerProtocol.swift
├─ Resources/
│  └─ config/
│     └─ default_profiles.json
└─ Build/                         # CI output artifacts (.app, .pkg, .dmg)
```

Note: The Xcode project is generated at build time using XcodeGen for reliability. The generated `.xcodeproj`/`.xcworkspace` are not committed; the CI workflow runs XcodeGen before building.


## Placeholders to Replace

Update these values across the project (CI workflow, scripts, Info.plists, and Xcode project settings):

- APP_BUNDLE_ID = com.yourcompany.DNSChanger
- HELPER_BUNDLE_ID = com.yourcompany.DNSChangerHelper
- HELPER_MACH_NAME = com.yourcompany.DNSChangerHelper.mach
- TEAM_ID = YOURTEAMID
- DEVELOPER_ID_APP = "Developer ID Application: Your Name (TEAMID)"
- APPLE_ID = your@appleid.com
- APP_SPECIFIC_PASSWORD = your_app_specific_password

These are typically provided via GitHub Secrets for CI:
- APPLE_ID
- APP_SPECIFIC_PASSWORD
- TEAM_ID
- DEVELOPER_ID_APP


## Security and SMJobBless Notes

- The privileged helper is installed with SMJobBless and runs as root.
- The app and helper must be signed with the same Team ID.
- The app Info.plist requires `SMPrivilegedExecutables` mapping `HELPER_BUNDLE_ID` to the helper’s designated code requirement. This project includes a build step that computes and injects the helper’s code requirement automatically during CI using `codesign -dr -` to avoid hardcoding.
- First run triggers an admin prompt to bless the helper. Subsequent operations require no further prompts.


## Build Overview

The CI workflow performs the following on macOS runners:

1. Checkout repository
2. Select Xcode
3. Install XcodeGen (to generate the Xcode project)
4. Generate `.xcodeproj`/`.xcworkspace` from `XcodeProject/project.yml`
5. Build a universal DNSChanger.app (Release)
6. Codesign the app (and embedded helper) with `DEVELOPER_ID_APP`
7. Package into `.pkg` and `.dmg`
8. Optionally notarize `.pkg` and `.dmg` if Apple credentials are provided
9. Verify Gatekeeper assessments
10. Upload artifacts and publish a GitHub Release


## Local Development

Prerequisites:
- Xcode 15+
- XcodeGen (brew install xcodegen)

Steps:
- Replace placeholders in `XcodeProject/project.yml` and Info.plist files (or provide via user-defined build settings)
- Run `xcodegen generate` inside `XcodeProject/`
- Open the generated `.xcworkspace` or `.xcodeproj`
- Select the `DNSChanger` scheme and run

Note: SMJobBless requires proper code signing to function. For local development, you may need to use a Developer ID Application certificate and configure the Team.


## CI Secrets & Signing

Set these GitHub Actions repository secrets:

- `DEVELOPER_ID_APP`: Your signing identity, e.g. `Developer ID Application: Your Name (TEAMID)`
- `APPLE_ID`: Your Apple ID used for notarization
- `APP_SPECIFIC_PASSWORD`: App-specific password for notarization
- `TEAM_ID`: Your Apple Team ID

If secrets are not provided, the workflow still builds artifacts but skips notarization.


## DNS Functionality

- Enumerates active services using `networksetup -listallnetworkservices` and `-getinfo` to filter active
- Apply DNS: `networksetup -setdnsservers "<service>" <ip1> <ip2> ...`
- Clear to DHCP: `networksetup -setdnsservers "<service>" Empty`
- Flush cache: `dscacheutil -flushcache` and `killall -HUP mDNSResponder`

These commands require root; the helper executes them.


## License

See LICENSE.


## Disclaimer

This project provides a reference implementation using SMJobBless. Review and adapt security posture for your organization’s policies. Always validate signing identities and requirements before distribution.
