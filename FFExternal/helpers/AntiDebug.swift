import Foundation
import Darwin

// MARK: - AntiDebug
//
// Anti-debugging, anti-Frida, anti-tamper.
// Called at startup and periodically in background.

enum AntiDebug {

    static func runChecks() {
        #if !targetEnvironment(simulator)
        if isBeingDebugged() || fridaDetected() || substrateDetected() || binaryTampered() {
            terminateProcess()
        }
        #endif
    }

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
        // Method 1: sysctl check for P_TRACED flag
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        sysctl(&mib, 4, &info, &size, nil, 0)
        if (info.kp_proc.p_flag & P_TRACED) != 0 { return true }

        // Method 2: PT_DENY_ATTACH via syscall (avoids direct ptrace symbol)
        // syscall(26) = ptrace, PT_DENY_ATTACH = 31
        #if arch(arm64)
        let result = syscall(26, 31, 0, 0, 0)
        if result != 0 { return true }
        #endif

        return false
    }

    // MARK: - Frida detection

    private static func fridaDetected() -> Bool {
        // Check for Frida gadget dynamic library
        let fridaNames = ["FridaGadget", "frida-agent", "frida_agent", "re.frida.Gadget"]
        for name in fridaNames {
            if dlopen(name, RTLD_NOLOAD | RTLD_NOW) != nil { return true }
        }

        // Check for Frida temp files
        let paths = ["/tmp/frida-", "/var/mobile/Library/Preferences/frida"]
        for p in paths {
            if FileManager.default.fileExists(atPath: p) { return true }
        }

        // Check for Frida default port 27042
        if portOpen(27042) { return true }

        return false
    }

    // MARK: - Substrate / hook detection

    private static func substrateDetected() -> Bool {
        let hookLibs = [
            "/usr/lib/libsubstrate.dylib",
            "/Library/MobileSubstrate/MobileSubstrate.dylib",
            "/usr/lib/TweakInject.dylib",
            "/var/jb/usr/lib/TweakInject.dylib",
        ]
        for path in hookLibs {
            if FileManager.default.fileExists(atPath: path) { return true }
        }
        return false
    }

    // MARK: - Binary integrity

    private static func binaryTampered() -> Bool {
        // Cracked IPA removes or replaces _CodeSignature
        let sig = Bundle.main.bundlePath + "/_CodeSignature/CodeResources"
        return !FileManager.default.fileExists(atPath: sig)
    }

    // MARK: - Port check

    private static func portOpen(_ port: UInt16) -> Bool {
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else { return false }
        defer { close(sock) }
        var addr = sockaddr_in()
        addr.sin_family      = sa_family_t(AF_INET)
        addr.sin_port        = port.bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        let r = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return r == 0
    }

    // MARK: - Terminate

    private static func terminateProcess() {
        raise(SIGKILL)
    }
}
