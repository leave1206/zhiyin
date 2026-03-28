import Cocoa
import Carbon

// MARK: - Zhiyin Menubar App
// Captures Globe/Fn key globally, triggers recording/transcription

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var isRecording = false
    var fnKeyMonitor: Any?
    var globalMonitor: Any?
    let zhiyinDir = NSHomeDirectory() + "/.zhiyin"

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create menubar icon
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateMenubarIcon()
        buildMenu()

        // Setup hotkey monitor
        setupHotkeyMonitor()

        let hotkey = readConfig("HOTKEY") ?? "right_cmd"
        NSLog("Zhiyin: Ready. Hotkey: \(hotkey)")
    }

    func setupHotkeyMonitor() {
        let hotkey = readConfig("HOTKEY") ?? "right_cmd"
        var rightCmdWasDown = false

        fnKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            switch hotkey {
            case "right_cmd":
                // Right Command: keyCode 54, detect press-and-release without other keys
                let cmdDown = event.modifierFlags.contains(.command)
                let noOthers = event.modifierFlags.intersection([.shift, .control, .option]).isEmpty

                if event.keyCode == 54 && cmdDown && noOthers {
                    rightCmdWasDown = true
                } else if event.keyCode == 54 && !cmdDown && rightCmdWasDown {
                    // Right Cmd released without other keys — toggle
                    rightCmdWasDown = false
                    self?.toggle()
                } else {
                    // Other modifier pressed during Cmd hold — cancel
                    rightCmdWasDown = false
                }

            case "fn":
                let fnFlag = event.modifierFlags.contains(.function)
                let noOthers = event.modifierFlags.intersection([.shift, .control, .option, .command]).isEmpty
                if fnFlag && noOthers {
                    self?.toggle()
                }

            default:
                break
            }
        }

        // F-key support via keyDown
        if hotkey.hasPrefix("f") && hotkey != "fn" {
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                switch hotkey {
                case "f5": if event.keyCode == 96 { self?.toggle() }
                case "f6": if event.keyCode == 97 { self?.toggle() }
                default: break
                }
            }
        }
    }

    func toggle() {
        if isRecording {
            stopAndTranscribe()
        } else {
            startRecording()
        }
    }

    func startRecording() {
        guard !isRecording else { return }
        isRecording = true
        updateMenubarIcon()

        // Kill any stale rec process
        cleanupStaleRecording()

        // Start recording via sox
        let wavFile = zhiyinDir + "/recording.wav"
        try? FileManager.default.removeItem(atPath: wavFile)

        // Use shell to launch rec with nohup (keeps recording alive)
        let logFile = zhiyinDir + "/voice.log"
        let pidFile = zhiyinDir + "/rec.pid"
        // Find rec in PATH (works for both /opt/homebrew and /usr/local)
        let shellCmd = "export PATH=/opt/homebrew/bin:/usr/local/bin:$PATH; nohup rec -q '\(wavFile)' >> '\(logFile)' 2>&1 & echo $! > '\(pidFile)'"

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.arguments = ["-c", shellCmd]
        do {
            try task.run()
            task.waitUntilExit()
            NSLog("Zhiyin: Recording started, PID file written")
        } catch {
            NSLog("Zhiyin: Failed to start recording: \(error)")
            isRecording = false
            updateMenubarIcon()
            return
        }

        // Timeout protection: auto-stop after MAX_DURATION seconds
        let maxDuration = Int(readConfig("MAX_DURATION") ?? "60") ?? 60
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(maxDuration)) { [weak self] in
            if self?.isRecording == true {
                self?.stopAndTranscribe()
            }
        }

        NSLog("Zhiyin: Recording started")
    }

    func stopAndTranscribe() {
        guard isRecording else { return }
        isRecording = false
        updateMenubarIcon()

        // Stop rec process
        let pidFile = zhiyinDir + "/rec.pid"
        if let pidStr = try? String(contentsOfFile: pidFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
           let pid = Int32(pidStr) {
            kill(pid, SIGTERM)
            usleep(300_000) // 0.3s
        }
        try? FileManager.default.removeItem(atPath: pidFile)

        // Run transcription, then set clipboard + paste via CGEvent
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let python = self.zhiyinDir + "/venv/bin/python3"
            let script = self.zhiyinDir + "/transcribe.py"

            let pipe = Pipe()
            let task = Process()
            task.executableURL = URL(fileURLWithPath: python)
            task.arguments = [script]
            task.currentDirectoryURL = URL(fileURLWithPath: "/tmp")
            task.standardOutput = pipe
            task.standardError = FileHandle.nullDevice
            try? task.run()
            task.waitUntilExit()

            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            // Log
            if let handle = FileHandle(forWritingAtPath: self.zhiyinDir + "/voice.log") {
                handle.seekToEndOfFile()
                handle.write((output + "\n").data(using: .utf8) ?? Data())
                handle.closeFile()
            }

            // Parse: ok|0.123|transcribed text
            if output.hasPrefix("ok|") {
                let parts = output.split(separator: "|", maxSplits: 2)
                if parts.count >= 3 {
                    let text = String(parts[2])
                    DispatchQueue.main.async {
                        // 1. Set clipboard via NSPasteboard
                        let pb = NSPasteboard.general
                        pb.clearContents()
                        pb.setString(text, forType: .string)
                        NSLog("Zhiyin: Clipboard set: \(text)")

                        // 2. Simulate Cmd+V via CGEvent
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            self.simulatePaste()
                        }
                    }
                }
            }

            NSLog("Zhiyin: Done: \(output)")
        }
    }

    func simulatePaste() {
        let src = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: true)  // V = 9
        let keyUp = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
        NSLog("Zhiyin: Cmd+V simulated")
    }

    func cleanupStaleRecording() {
        let pidFile = zhiyinDir + "/rec.pid"
        guard let pidStr = try? String(contentsOfFile: pidFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
              let pid = Int32(pidStr) else { return }

        // Check if process is alive
        if kill(pid, 0) == 0 {
            kill(pid, SIGTERM)
            usleep(300_000)
        }
        try? FileManager.default.removeItem(atPath: pidFile)
        try? FileManager.default.removeItem(atPath: zhiyinDir + "/recording.wav")
    }

    func updateMenubarIcon() {
        DispatchQueue.main.async {
            if self.isRecording {
                self.statusItem.button?.title = "🔴"
            } else {
                self.statusItem.button?.title = "🎤"
            }
        }
    }

    func buildMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "zhiyin 知音 — Offline Voice Input", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())

        let hotkey = readConfig("HOTKEY") ?? "right_cmd"
        let hotkeyLabel = hotkey == "right_cmd" ? "Right ⌘" : hotkey.uppercased()
        let toggleItem = NSMenuItem(title: "Toggle Recording (\(hotkeyLabel))", action: #selector(menuToggle), keyEquivalent: "")
        toggleItem.target = self
        menu.addItem(toggleItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc func menuToggle() { toggle() }

    @objc func quitApp() {
        cleanupStaleRecording()
        NSApplication.shared.terminate(nil)
    }

    func readConfig(_ key: String) -> String? {
        let configFile = zhiyinDir + "/zhiyin.conf"
        guard let content = try? String(contentsOfFile: configFile, encoding: .utf8) else { return nil }
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") || trimmed.isEmpty { continue }
            let parts = trimmed.components(separatedBy: "=")
            if parts.count >= 2 && parts[0].trimmingCharacters(in: .whitespaces) == key {
                return parts[1].trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }
}

// MARK: - Main
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory) // Menubar only, no dock icon
app.run()
