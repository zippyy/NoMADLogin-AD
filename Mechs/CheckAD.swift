//
//  CheckAD.swift
//  NoMADLogin
//
//  Created by Joel Rennich on 9/20/17.
//

import Cocoa
import IOKit
import os.log

/// The AuthorizationPlugin callbacks are not guaranteed to arrive on the main
/// thread. AppKit windows shown by SecurityAgent must be created, presented,
/// and torn down on the main thread.
@objc final class CheckAD: NoLoMechanism {
    @objc var signIn: SignIn?

    @objc func run() {
        os_log("CheckAD mech starting", log: checkADLog, type: .debug)

        if useAutologin() {
            os_log("Using autologin", log: checkADLog, type: .debug)
            allowLogin()
            os_log("CheckAD mech complete", log: checkADLog, type: .debug)
            return
        }

        let present: () -> Void = { [weak self] in
            self?.presentLoginWindow()
        }

        if Thread.isMainThread {
            present()
        } else {
            // The mechanism thread waits while its modal login UI is active,
            // so synchronously entering the main queue preserves the original
            // authorization flow without touching AppKit off-main-thread.
            DispatchQueue.main.sync {
                present()
            }
        }

        os_log("CheckAD mech complete", log: checkADLog, type: .debug)
    }

    private func presentLoginWindow() {
        precondition(Thread.isMainThread)

        os_log("Activating app", log: checkADLog, type: .debug)
        NSApplication.shared.activate(ignoringOtherApps: true)

        os_log("Loading XIB", log: checkADLog, type: .debug)
        let controller = SignIn(windowNibName: NSNib.Name("SignIn"))
        controller.mech = mech

        if let domain = managedDomain {
            os_log("Set managed domain for loginwindow", log: checkADLog, type: .debug)
            controller.domainName = domain.uppercased()
        }
        if let required = isSSLRequired {
            os_log("Set SSL required", log: checkADLog, type: .debug)
            controller.isSSLRequired = required
        }

        guard let loginWindow = controller.window else {
            os_log("Could not create login window UI", log: checkADLog, type: .error)
            denyLogin()
            return
        }

        signIn = controller
        os_log("Displaying window", log: checkADLog, type: .debug)
        NSApplication.shared.runModal(for: loginWindow)
    }

    @objc func tearDown() {
        os_log("Got teardown request", log: checkADLog, type: .debug)

        let closeUI: () -> Void = { [weak self] in
            self?.signIn?.loginTransition()
        }
        if Thread.isMainThread {
            closeUI()
        } else {
            DispatchQueue.main.async {
                closeUI()
            }
        }
    }

    func useAutologin() -> Bool {
        if UserDefaults(suiteName: "com.apple.loginwindow")?.bool(forKey: "DisableFDEAutoLogin") ?? false {
            os_log("FDE AutoLogin Disabled per loginwindow preference key", log: checkADLog, type: .debug)
            return false
        }

        os_log("Checking for autologin.", log: checkADLog, type: .default)
        if FileManager.default.fileExists(atPath: "/tmp/nolorun") {
            os_log("NoLo has run once already. Load regular window as this isn't a reboot", log: checkADLog, type: .debug)
            return false
        }

        os_log("NoLo hasn't run, trying autologin", log: checkADLog, type: .debug)
        try? "Run Once".write(to: URL(fileURLWithPath: "/tmp/nolorun"), atomically: true, encoding: .utf8)

        if let uuid = getEFIUUID(), let name = NoLoMechanism.getShortname(uuid: uuid) {
            setContextString(type: kAuthorizationEnvironmentUsername, value: name)
        }
        return true
    }

    private func getEFIUUID() -> String? {
        let chosen = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/chosen")
        guard chosen != 0 else { return nil }
        defer { IOObjectRelease(chosen) }

        var properties: Unmanaged<CFMutableDictionary>?
        let result = IORegistryEntryCreateCFProperties(chosen, &properties, kCFAllocatorDefault, 0)
        guard result == KERN_SUCCESS,
              let dictionary = properties?.takeRetainedValue() as? [String: Any],
              let uuid = dictionary["efilogin-unlock-ident"] as? Data else {
            return nil
        }

        return String(data: uuid, encoding: .utf8)
    }
}
