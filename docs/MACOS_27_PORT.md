# macOS 27 port

This branch ports the build pipeline to current Xcode/macOS SDKs while retaining the existing SecurityAgent authorization plug-in architecture.

## What changed

- `NoMAD_ADAuth.framework` is rebuilt from its source release instead of using the old Carthage binary committed with the historical project.
- The dependency and plug-in are built as universal `arm64` + `x86_64` binaries.
- The build runs in Swift 5 language mode with minimal strict-concurrency checking. This is deliberate: moving an authorization plug-in to Swift 6 language mode requires a separate full concurrency audit.
- The login-window AppKit work in `CheckAD` now always runs on the main thread, and modern IOKit APIs are used to read the FileVault login UUID.
- The shared scheme no longer edits `Info.plist` after every build. That old post-build mutation made reproducible signing and notarization unreliable.
- GitHub Actions produces an **ad-hoc signed validation artifact**. It is not a deployable or notarized release.

## Build a Developer ID release

Install a current Xcode release and ensure the Developer ID Application identity is present in your login keychain. Then run:

```bash
cd NoMADLogin-AD
CODE_SIGN_IDENTITY='Developer ID Application: Your Company (TEAMID)' \
DEVELOPMENT_TEAM=TEAMID \
bash Scripts/build-macos27.sh
```

The signed bundle is written to:

```text
build/NoMADLoginAD-DerivedData/Build/Products/Release/NoMADLoginAD.bundle
```

The build script does all of the following:

1. checks out NoMAD-ADAuth `1.1.4` from source;
2. builds a universal framework with the current SDK;
3. builds the NoMAD login bundle with `Config/ModernMacOS.xcconfig`;
4. signs the embedded framework before signing the outer plug-in; and
5. verifies universal architectures and nested code signatures.

## Test before deployment

Do **not** replace the plug-in on a production Mac first. Test on a disposable macOS 27 installation with a known local administrator account and physical/recovery access.

Validate each of these paths:

- normal AD login and just-in-time local account creation;
- existing local-account sign-in and local fallback;
- logout and a second login without network access;
- FileVault preboot unlock followed by automatic desktop login;
- password change and password overwrite flows, if enabled;
- external display and multiple-display login UI behavior; and
- recovery after deliberately disabling or removing the plug-in.

## Recovery

Keep an SSH session or physical admin access available before changing `system.login.console`. To return to Apple's standard login window, run:

```bash
sudo /usr/local/bin/authchanger -reset
sudo killall -HUP loginwindow
```

If the Mac cannot reach a usable login window, boot to Recovery and remove the installed bundle from:

```text
/Library/Security/SecurityAgentPlugins/NoMADLoginAD.bundle
```

Then restart and repair the authorization database with the bundled `authchanger` tool after booting normally.

## Scope

This is a build and runtime compatibility port, not a claim that Apple considers third-party SecurityAgent plug-ins a stable long-term loginwindow extension point. Keep the test matrix above as part of every major macOS upgrade.
