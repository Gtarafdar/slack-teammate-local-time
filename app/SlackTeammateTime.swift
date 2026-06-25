// SlackTeammateTime.swift
//
// A tiny macOS menu bar app that:
//   * On first launch (from the DMG/Downloads), installs itself to
//     ~/Applications, deploys the background engine, and registers a login item.
//   * Lives in the menu bar with an on/off toggle for the inline teammate times.
//     Toggling writes state.json; the background injector applies it to Slack
//     live (no reload), so labels appear/disappear instantly.
//
// Universal build (Intel + Apple Silicon). No external dependencies.

import Cocoa

let fm = FileManager.default
let home = fm.homeDirectoryForCurrentUser

let stableAppURL   = home.appendingPathComponent("Applications/SlackTeammateTime.app")
let appSupportURL  = home.appendingPathComponent("Library/Application Support/SlackTeammateTime")
let stateURL       = appSupportURL.appendingPathComponent("state.json")
let launchAgentsURL = home.appendingPathComponent("Library/LaunchAgents")
let enginePlistURL = launchAgentsURL.appendingPathComponent("com.user.slacktime.plist")
let menuPlistURL   = launchAgentsURL.appendingPathComponent("com.user.slacktime.menubar.plist")
let bundleId = "com.user.slackteammatetime"

// MARK: - Helpers

@discardableResult
func runProcess(_ launchPath: String, _ args: [String]) -> Int32 {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: launchPath)
    p.arguments = args
    do { try p.run() } catch { return -1 }
    p.waitUntilExit()
    return p.terminationStatus
}

func clearQuarantine(_ url: URL) {
    runProcess("/usr/bin/xattr", ["-dr", "com.apple.quarantine", url.path])
}

func setupScriptURL() -> URL? {
    return Bundle.main.resourceURL?.appendingPathComponent("setup.sh")
}

func runtimeSrcURL() -> URL? {
    return Bundle.main.resourceURL?.appendingPathComponent("runtime")
}

@discardableResult
func runSetupInstall() -> Bool {
    guard let setup = setupScriptURL(), let runtime = runtimeSrcURL() else { return false }
    return runProcess("/bin/bash", [setup.path, "install", runtime.path]) == 0
}

@discardableResult
func runSetupUninstall() -> Bool {
    guard let setup = setupScriptURL() else { return false }
    return runProcess("/bin/bash", [setup.path, "uninstall"]) == 0
}

func xmlEscape(_ s: String) -> String {
    return s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
}

func writeMenuLoginAgent() {
    let exec = xmlEscape(stableAppURL.appendingPathComponent("Contents/MacOS/SlackTeammateTime").path)
    let plist = """
    <?xml version="1.0" encoding="UTF-8"?>
    <plist version="1.0">
    <dict>
        <key>Label</key><string>com.user.slacktime.menubar</string>
        <key>ProgramArguments</key>
        <array>
            <string>\(exec)</string>
        </array>
        <key>RunAtLoad</key><true/>
        <key>KeepAlive</key><false/>
        <key>ProcessType</key><string>Interactive</string>
    </dict>
    </plist>
    """
    try? fm.createDirectory(at: launchAgentsURL, withIntermediateDirectories: true)
    try? plist.write(to: menuPlistURL, atomically: true, encoding: .utf8)
}

// Start (and register for login) the menu bar app via launchd. RunAtLoad makes
// it appear immediately, and the agent relaunches it at every login.
func loadMenuLoginAgent() {
    runProcess("/bin/launchctl", ["unload", menuPlistURL.path])
    runProcess("/bin/launchctl", ["load", menuPlistURL.path])
}

func readEnabled() -> Bool {
    guard let data = try? Data(contentsOf: stateURL),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let e = obj["enabled"] as? Bool else { return true }
    return e
}

func writeEnabled(_ value: Bool) {
    try? fm.createDirectory(at: appSupportURL, withIntermediateDirectories: true)
    if let data = try? JSONSerialization.data(withJSONObject: ["enabled": value],
                                              options: [.prettyPrinted]) {
        try? data.write(to: stateURL)
    }
}

func engineInstalled() -> Bool {
    return fm.fileExists(atPath: enginePlistURL.path)
}

func anotherStableInstanceRunning() -> Bool {
    let me = stableAppURL.resolvingSymlinksInPath()
    let myPid = ProcessInfo.processInfo.processIdentifier
    for app in NSWorkspace.shared.runningApplications {
        guard app.bundleIdentifier == bundleId, app.processIdentifier != myPid else { continue }
        if app.bundleURL?.resolvingSymlinksInPath() == me { return true }
    }
    return false
}

// MARK: - App delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var toggleItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let myURL = Bundle.main.bundleURL.resolvingSymlinksInPath()
        let stable = stableAppURL.resolvingSymlinksInPath()

        if myURL != stable {
            runInstallerFlow()   // launched from DMG/Downloads
        } else {
            runMenuBar()         // launched from ~/Applications (login or click)
        }
    }

    // First-run: copy to ~/Applications, deploy engine, register login item.
    func runInstallerFlow() {
        NSApp.activate(ignoringOtherApps: true)

        // Copy self into ~/Applications (stable path for the login item).
        do {
            try fm.createDirectory(at: stableAppURL.deletingLastPathComponent(),
                                   withIntermediateDirectories: true)
            if fm.fileExists(atPath: stableAppURL.path) {
                try fm.removeItem(at: stableAppURL)
            }
            try fm.copyItem(at: Bundle.main.bundleURL, to: stableAppURL)
            clearQuarantine(stableAppURL)
        } catch {
            showAlert(title: "Install failed",
                      text: "Could not copy the app to your Applications folder.\n\n\(error.localizedDescription)",
                      style: .critical)
            NSApp.terminate(nil)
            return
        }

        let ok = runSetupInstall()
        writeMenuLoginAgent()
        // Start the menu bar app now (and register it for login).
        loadMenuLoginAgent()

        if !ok {
            showAlert(title: "Install issue",
                      text: "The app installed but the background helper did not start. Try opening the app again from your Applications folder.",
                      style: .warning)
        } else {
            showAlert(title: "Installed",
                      text: "Slack Teammate Time is on. Teammates' local times now appear next to their names in Slack.\n\nUse the clock icon in your menu bar to turn it on or off anytime. It starts automatically when you log in.",
                      style: .informational)
        }

        // The launchd-started copy is now the live menu bar app; quit this
        // (Downloads/DMG) instance.
        NSApp.terminate(nil)
    }

    // Steady state: show the menu bar item.
    func runMenuBar() {
        if anotherStableInstanceRunning() { NSApp.terminate(nil); return }

        // Self-heal if the engine isn't set up yet.
        if !engineInstalled() {
            runSetupInstall()
            writeMenuLoginAgent()
        }
        if !fm.fileExists(atPath: stateURL.path) { writeEnabled(true) }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            if let img = NSImage(systemSymbolName: "clock", accessibilityDescription: "Slack Teammate Time") {
                img.isTemplate = true
                button.image = img
            } else {
                button.title = "🕒"
            }
        }

        let menu = NSMenu()
        let header = NSMenuItem(title: "Slack Teammate Time", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        let toggle = NSMenuItem(title: "Show teammate times",
                                action: #selector(toggleEnabled), keyEquivalent: "")
        toggle.target = self
        toggle.state = readEnabled() ? .on : .off
        menu.addItem(toggle)
        self.toggleItem = toggle

        menu.addItem(.separator())
        let uninstall = NSMenuItem(title: "Uninstall…",
                                   action: #selector(uninstall), keyEquivalent: "")
        uninstall.target = self
        menu.addItem(uninstall)

        let quit = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        item.menu = menu
        self.statusItem = item
    }

    @objc func toggleEnabled() {
        let newValue = !readEnabled()
        writeEnabled(newValue)
        toggleItem?.state = newValue ? .on : .off
    }

    @objc func uninstall() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Remove Slack Teammate Time?"
        alert.informativeText = "This stops and removes the helper and its login item. Slack itself is not affected."
        alert.addButton(withTitle: "Uninstall")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        if alert.runModal() == .alertFirstButtonReturn {
            runSetupUninstall()
            try? fm.removeItem(at: menuPlistURL)
            // Remove the app bundle on next launch cycle (can't delete while running
            // reliably, but try anyway).
            try? fm.removeItem(at: stableAppURL)
            showAlert(title: "Removed",
                      text: "Slack Teammate Time has been removed. Quit and reopen Slack to clear any remaining labels.",
                      style: .informational)
            NSApp.terminate(nil)
        }
    }

    @objc func quitApp() {
        NSApp.terminate(nil)
    }

    func showAlert(title: String, text: String, style: NSAlert.Style) {
        // SLACKTIME_SILENT=1 suppresses dialogs (used for automated testing).
        if ProcessInfo.processInfo.environment["SLACKTIME_SILENT"] == "1" {
            print("ALERT [\(title)] \(text)")
            return
        }
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.alertStyle = style
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

// MARK: - Entry point

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
