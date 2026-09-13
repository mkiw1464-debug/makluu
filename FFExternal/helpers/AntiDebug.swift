import Foundation
import Darwin

// MARK: - AntiDebug
//
// Layered anti-debugging and anti-tampering protection.
// Kills the process if a debugger, Frida, or Substrate is detected.
// Called once at app startup and periodically.

enum AntiDebug {

    // MARK: - Public API

    /// Run all checks. Call from App.init() and periodically.
    static func runChecks() {
        #if !targetEnvironment(simulator)
        if isBeingDebugged() || fridaDetected() || substrateDetected() || binaryTampered() {
            terminateProcess()
        }
        #endif
    }

    /// Background periodic check (every 30s).
    static func startPeriodicChecks() {
        #if !targetEnvironment(simulator)
        Thread.detachNewThread {
            while true {
                Thread.sleep(forTimeInterval: Double.random(in: 25...35))
                if isBeingDebugged() || fridaDetected() || substrateDetected() {
                    terminateProcess()
                }
            }
        }
        #endif
    }

    // MARK: - Debugger detection

    private static func isBeingDebugged() -> Bool {
        // Method 1: sysctl PT_DENY_ATTACH
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        sysctl(&mib, 4, &info, &size, nil, 0)
        if (info.kp_proc.p_flag & P_TRACED) != 0 { return true }

        // Method 2: ptrace self-attach (prevents external debugger)
        if ptrace(PT_DENY_ATTACH, 0, nil, 0) != 0 { return true }

        // Method 3: SIGTRAP test
        // (skip — too aggressive for normal operation)

        return false
    }

    // MARK: - Frida detection

    private static func fridaDetected() -> Bool {
        // Method 1: Check for Frida gadget library
        let fridaLibs = [
            "FridaGadget",
            "frida-agent",
            "frida_agent",
            "re.frida.Gadget",
        ]
        for lib in fridaLibs {
            if dlopen(lib, RTLD_NOLOAD) != nil { return true }
        }

        // Method 2: Check for Frida named pipe
        let fridaPipes = [
            "/tmp/frida-",
            "/var/mobile/Library/Preferences/frida",
        ]
        let fm = FileManager.default
        for pipe in fridaPipes {
            if fm.fileExists(atPath: pipe) { return true }
        }

        // Method 3: Unexpected open port 27042 (Frida default)
        if checkPort(27042) { return true }

        return false
    }

    // MARK: - Substrate / Dobby detection

    private static func substrateDetected() -> Bool {
        // Check if our own methods have been hooked
        // Substrate patches the first few bytes of functions
        // If a function starts with a jump instruction, it's hooked

        // Check ptrace itself for hooks
        if let sym = dlsym(RTLD_DEFAULT, "ptrace") {
            let ptr = sym.assumingMemoryBound(to: UInt8.self)
            // ARM64: BL/BLR starts with 0x94/0xD6, B starts with 0x14
            // Substrate hook typically starts with 0x58 (LDR) or 0xE5 (BL)
            let firstByte = ptr.pointee
            if firstByte == 0xE5 || firstByte == 0x58 { return true }
        }

        // Check for known hook libraries
        let hookLibs = [
            "/usr/lib/libsubstrate.dylib",
            "/usr/lib/substrate",
            "/Library/MobileSubstrate/MobileSubstrate.dylib",
            "/usr/lib/TweakInject.dylib",
            "/var/jb/usr/lib/TweakInject.dylib",
        ]
        for lib in hookLibs {
            if FileManager.default.fileExists(atPath: lib) { return true }
        }

        return false
    }

    // MARK: - Binary integrity check

    private static func binaryTampered() -> Bool {
        // Compare code signature presence
        // A cracked IPA removes or replaces code signature
        guard let execPath = Bundle.main.executablePath else { return false }
        let fm = FileManager.default
        guard fm.fileExists(atPath: execPath) else { return true }

        // Check _CodeSignature exists
        let codeSignPath = Bundle.main.bundlePath + "/_CodeSignature/CodeResources"
        if !fm.fileExists(atPath: codeSignPath) { return true }

        return false
    }

    // MARK: - Port check helper

    private static func checkPort(_ port: UInt16) -> Bool {
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else { return false }
        defer { close(sock) }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port   = port.bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        let result = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return result == 0
    }

    // MARK: - Terminate

    private static func terminateProcess() {
        // Hard kill — no clean shutdown
        raise(SIGKILL)
        exit(0)
    }
}
