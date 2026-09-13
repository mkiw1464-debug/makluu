import Foundation
import UIKit
import Darwin
import Combine

// MARK: - String Decryptor

private enum _X {
    static let k: UInt8 = 0x5A
    static func d(_ b: [UInt8]) -> String {
        String(bytes: b.map { $0 ^ k }, encoding: .utf8) ?? ""
    }
}

// MARK: - Global logger

class AppLog: ObservableObject {
    static let shared = AppLog()
    @Published var entries: [String] = []
    func append(_ msg: String) {
        DispatchQueue.main.async { self.entries.append(msg) }
    }
}

// Log prefix "[FFExt]" — decoded at runtime, never in binary as plaintext
private let _lp: String = {
    _X.d([0x01, 0x1c, 0x1c, 0x1f, 0x22, 0x2e, 0x07])
}()

func log(_ msg: String) { AppLog.shared.append("\(_lp) \(msg)") }

private var logCapturePipe: Pipe?

func setupLogCapture() {
    guard logCapturePipe == nil else { return }
    let pipe = Pipe()
    logCapturePipe = pipe
    setvbuf(stdout, nil, _IONBF, 0)
    setvbuf(stderr, nil, _IONBF, 0)
    let writeFd = pipe.fileHandleForWriting.fileDescriptor
    if dup2(writeFd, STDOUT_FILENO) < 0 || dup2(writeFd, STDERR_FILENO) < 0 {
        logCapturePipe = nil
        return
    }
    pipe.fileHandleForReading.readabilityHandler = { handle in
        let data = handle.availableData
        guard !data.isEmpty else { return }
        if let text = String(data: data, encoding: .utf8) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                DispatchQueue.main.async { AppLog.shared.append(trimmed) }
            }
        }
    }
}

// MARK: - App Info

enum AppInfo {
    static var osVersion: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }
    static var versionTuple: (major: Int, minor: Int, patch: Int) {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return (v.majorVersion, v.minorVersion, v.patchVersion)
    }
    static var osBuild: String {
        var size: size_t = 0
        guard sysctlbyname("kern.osversion", nil, &size, nil, 0) == 0, size > 0 else { return "Unknown" }
        var value = [CChar](repeating: 0, count: size)
        guard sysctlbyname("kern.osversion", &value, &size, nil, 0) == 0 else { return "Unknown" }
        return String(cString: value)
    }
    static var machineName: String {
        var s = utsname(); uname(&s)
        return Mirror(reflecting: s.machine).children.reduce("") { id, e in
            guard let v = e.value as? Int8, v != 0 else { return id }
            return id + String(UnicodeScalar(UInt8(v)))
        }
    }
    static var displayMachineName: String {
        #if targetEnvironment(simulator)
        return ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? machineName
        #else
        return machineName
        #endif
    }
}

// MARK: - Exploit Status

enum ExploitStatus: Equatable {
    case notStarted
    case success(method: String)
    case failed(method: String, code: Int64)
    case unsupported(String)

    var isSuccess: Bool { if case .success = self { return true }; return false }
    var isFailed: Bool { if case .failed = self { return true }; return false }
    var displayText: String {
        switch self {
        case .notStarted:           return "Not attempted"
        case .success(let m):       return "OK via \(m)"
        case .failed(let m, let c): return "FAILED \(m) (\(c))"
        case .unsupported(let m):   return "Unsupported: \(m)"
        }
    }
}

// MARK: - App Paths

enum AppPaths {
    // "ffext_backups" decoded at runtime
    private static let _bd: [UInt8] = [0x3c, 0x3c, 0x3f, 0x22, 0x2e, 0x05,
                                        0x38, 0x3b, 0x39, 0x31, 0x2f, 0x2a, 0x29]

    static var backups: String {
        let u = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let b = u.appendingPathComponent(_X.d(_bd), isDirectory: true)
        try? FileManager.default.createDirectory(at: b, withIntermediateDirectories: true)
        return b.path
    }
    static var backupsURL: URL { URL(fileURLWithPath: backups, isDirectory: true) }
}
