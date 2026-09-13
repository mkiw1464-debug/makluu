import Foundation
import UIKit

// MARK: - String Decryptor

private enum _X {
    static let k: UInt8 = 0x5A
    static func d(_ b: [UInt8]) -> String {
        String(bytes: b.map { $0 ^ k }, encoding: .utf8) ?? ""
    }
}

// MARK: - Models

struct LicenseResponse: Codable {
    let valid: Bool
    let status: String?
    let expiresAt: String?
    let hwid: String?

    enum CodingKeys: String, CodingKey {
        case valid
        case status
        case expiresAt = "expires_at"
        case hwid
    }
}

struct LicenseInfo {
    let key: String
    let expiresAt: String
    let expiryDate: Date?
    let deviceName: String
    let hwid: String
    let iOSVersion: String
    let iPhoneModel: String
}

// MARK: - HWID

enum DeviceID {
    private static let _hk: [UInt8] = [0x3c, 0x3c, 0x3f, 0x22, 0x2e, 0x05, 0x32, 0x2d, 0x33, 0x3e]
    private static let _hp: [UInt8] = [0x33, 0x35, 0x29, 0x77]

    static var hwid: String {
        let key = _X.d(_hk)
        if let stored = UserDefaults.standard.string(forKey: key) {
            return stored
        }
        let raw = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        let hwid = _X.d(_hp) + raw.prefix(16).lowercased()
        UserDefaults.standard.set(hwid, forKey: key)
        return hwid
    }

    static var deviceName: String {
        UIDevice.current.name
    }

    static var iPhoneModel: String {
        var size: size_t = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        var machine = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.machine", &machine, &size, nil, 0)
        let identifier = String(cString: machine)
        return iPhoneModelName(from: identifier)
    }

    static var iOSVersion: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }

    private static func iPhoneModelName(from identifier: String) -> String {
        let map: [String: String] = [
            "iPhone17,1": "iPhone 16 Pro Max",
            "iPhone17,2": "iPhone 16 Pro",
            "iPhone17,3": "iPhone 16 Plus",
            "iPhone17,4": "iPhone 16",
            "iPhone16,1": "iPhone 15 Pro Max",
            "iPhone16,2": "iPhone 15 Pro",
            "iPhone15,4": "iPhone 15 Plus",
            "iPhone15,5": "iPhone 15",
            "iPhone15,2": "iPhone 14 Pro Max",
            "iPhone15,3": "iPhone 14 Pro",
            "iPhone14,7": "iPhone 14 Plus",
            "iPhone14,8": "iPhone 14",
            "iPhone14,2": "iPhone 13 Pro",
            "iPhone14,3": "iPhone 13 Pro Max",
            "iPhone14,4": "iPhone 13 Mini",
            "iPhone14,5": "iPhone 13",
            "iPhone13,1": "iPhone 12 Mini",
            "iPhone13,2": "iPhone 12",
            "iPhone13,3": "iPhone 12 Pro",
            "iPhone13,4": "iPhone 12 Pro Max",
            "iPhone12,1": "iPhone 11",
            "iPhone12,3": "iPhone 11 Pro",
            "iPhone12,5": "iPhone 11 Pro Max",
            "arm64":      "Simulator",
            "x86_64":     "Simulator",
        ]
        return map[identifier] ?? identifier
    }
}

// MARK: - Service

enum LicenseService {
    // XOR-encoded strings — decoded at runtime only
    private static let _au: [UInt8] = [0x32, 0x2e, 0x2e, 0x2a, 0x29, 0x60, 0x75, 0x75,
                                        0x3c, 0x3c, 0x3f, 0x22, 0x22, 0x22, 0x22, 0x74,
                                        0x2c, 0x3f, 0x28, 0x39, 0x3f, 0x36, 0x74, 0x3b,
                                        0x2a, 0x2a, 0x75, 0x3b, 0x2a, 0x33, 0x75, 0x36,
                                        0x33, 0x39, 0x3f, 0x34, 0x29, 0x3f, 0x29, 0x75,
                                        0x2c, 0x3b, 0x36, 0x33, 0x3e, 0x3b, 0x2e, 0x3f]
    private static let _sk: [UInt8] = [0x3c, 0x3c, 0x3f, 0x22, 0x2e, 0x05, 0x36, 0x33,
                                        0x39, 0x3f, 0x34, 0x29, 0x3f, 0x05, 0x31, 0x3f, 0x23]
    private static let _ek: [UInt8] = [0x3c, 0x3c, 0x3f, 0x22, 0x2e, 0x05, 0x36, 0x33,
                                        0x39, 0x3f, 0x34, 0x29, 0x3f, 0x05, 0x3f, 0x22,
                                        0x2a, 0x33, 0x28, 0x23]
    private static let _hk: [UInt8] = [0x3c, 0x3c, 0x3f, 0x22, 0x2e, 0x05, 0x36, 0x33,
                                        0x39, 0x3f, 0x34, 0x29, 0x3f, 0x05, 0x32, 0x2d,
                                        0x33, 0x3e]

    static var apiURL:      URL    { URL(string: _X.d(_au))! }
    static var storageKey:  String { _X.d(_sk) }
    static var expiryKey:   String { _X.d(_ek) }
    static var hwidLockKey: String { _X.d(_hk) }

    // MARK: - Validate (login)

    static func validate(key: String) async throws -> LicenseInfo {
        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        let body: [String: Any] = [
            "key":  key,
            "hwid": DeviceID.hwid
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw LicenseError.networkError
        }
        guard (200..<300).contains(http.statusCode) else {
            throw LicenseError.serverError(http.statusCode)
        }

        let decoded = try JSONDecoder().decode(LicenseResponse.self, from: data)
        guard decoded.valid else {
            throw LicenseError.invalidKey
        }

        if let serverHwid = decoded.hwid, !serverHwid.isEmpty {
            if serverHwid != DeviceID.hwid {
                throw LicenseError.deviceMismatch
            }
        }

        let expiresAtRaw  = decoded.expiresAt ?? ""
        let expiryDate    = parseISODate(expiresAtRaw)
        let formattedExpiry = expiryDate.map { formatDate($0) } ?? expiresAtRaw

        if let exp = expiryDate, exp < Date() {
            throw LicenseError.expired
        }

        let info = LicenseInfo(
            key:          key,
            expiresAt:    formattedExpiry,
            expiryDate:   expiryDate,
            deviceName:   DeviceID.deviceName,
            hwid:         DeviceID.hwid,
            iOSVersion:   DeviceID.iOSVersion,
            iPhoneModel:  DeviceID.iPhoneModel
        )
        store(key: key, expiryRaw: expiresAtRaw)
        return info
    }

    // MARK: - Auto-session restore
    // 
    // FIXED: sebelum ni hanya check local expiry — key banned/deleted kat server
    // still boleh masuk. Sekarang validate dengan server dulu, kalau server reject
    // (banned, deleted, expired, device mismatch) terus auto-logout.
    // 
    // Returns nil instantly jika tiada stored key.
    // Caller perlu await — panggil dari .task atau async context.

    static func restoreSession() async -> LicenseInfo? {
        guard let key = storedKey() else { return nil }

        // Fast local check: kalau expired locally, buang terus tanpa perlukan network
        if let expRaw = UserDefaults.standard.string(forKey: expiryKey),
           let expDate = parseISODate(expRaw),
           expDate < Date() {
            logout()
            return nil
        }

        // Server-side validation — tangkap ban, delete, dan expire sebenar
        do {
            let info = try await validate(key: key)
            return info
        } catch {
            // Semua error dari server (invalid, expired, banned, device mismatch)
            // → logout dan paksa login semula
            logout()
            return nil
        }
    }

    // Synchronous restore (local-only) — digunakan untuk fast UI bootstrap
    // sebelum async server check siap. Caller wajib follow up dengan
    // restoreSession() async untuk server validation.
    static func restoreSessionLocal() -> LicenseInfo? {
        guard let key    = storedKey(),
              let expRaw = UserDefaults.standard.string(forKey: expiryKey) else {
            return nil
        }
        let expiryDate = parseISODate(expRaw)
        if let exp = expiryDate, exp < Date() {
            logout()
            return nil
        }
        return LicenseInfo(
            key:         key,
            expiresAt:   expiryDate.map { formatDate($0) } ?? expRaw,
            expiryDate:  expiryDate,
            deviceName:  DeviceID.deviceName,
            hwid:        DeviceID.hwid,
            iOSVersion:  DeviceID.iOSVersion,
            iPhoneModel: DeviceID.iPhoneModel
        )
    }

    // MARK: - Periodic re-validation
    // Dipanggil dari MainMenuView timer setiap 60 saat untuk tangkap
    // mid-session ban/delete tanpa perlu restart app.

    static func revalidateBackground(key: String) async -> Bool {
        do {
            _ = try await validate(key: key)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Storage

    static func storedKey() -> String? {
        UserDefaults.standard.string(forKey: storageKey)
    }

    private static func store(key: String, expiryRaw: String) {
        UserDefaults.standard.set(key, forKey: storageKey)
        UserDefaults.standard.set(expiryRaw, forKey: expiryKey)
    }

    static func logout() {
        UserDefaults.standard.removeObject(forKey: storageKey)
        UserDefaults.standard.removeObject(forKey: expiryKey)
    }

    // MARK: - Helpers

    private static func parseISODate(_ raw: String) -> Date? {
        let fmt1 = ISO8601DateFormatter()
        fmt1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = fmt1.date(from: raw) { return d }
        let fmt2 = ISO8601DateFormatter()
        fmt2.formatOptions = [.withInternetDateTime]
        return fmt2.date(from: raw)
    }

    private static func formatDate(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        return df.string(from: date)
    }

    static func maskedKey(_ key: String) -> String {
        // FFEX-A3F9-B21C-7D4E → FFEX-A3••-••••-••4E
        // First segment: fully visible (prefix identifier)
        // Second segment: first 2 chars visible, rest masked
        // Middle segments: fully masked
        // Last segment: last 2 chars visible, rest masked
        let parts = key.components(separatedBy: "-")
        guard parts.count >= 2 else {
            let n = key.count
            guard n > 4 else { return String(repeating: "•", count: n) }
            return String(repeating: "•", count: n - 2)
                + String(key.suffix(2))
        }

        func maskSeg(_ s: String, showStart: Int = 0, showEnd: Int = 0) -> String {
            let n = s.count
            guard n > showStart + showEnd else { return s }
            let start = showStart > 0 ? String(s.prefix(showStart)) : ""
            let end   = showEnd   > 0 ? String(s.suffix(showEnd))   : ""
            let dots  = String(repeating: "•", count: n - showStart - showEnd)
            return start + dots + end
        }

        var masked: [String] = []
        for (i, part) in parts.enumerated() {
            if i == 0 {
                masked.append(part)                          // FFEX — keep full
            } else if i == 1 {
                masked.append(maskSeg(part, showStart: 2))  // A3••
            } else if i == parts.count - 1 {
                masked.append(maskSeg(part, showEnd: 2))    // ••4E
            } else {
                masked.append(maskSeg(part))                 // ••••
            }
        }
        return masked.joined(separator: "-")
    }

    static func countdownString(from expiryDate: Date) -> String {
        let now = Date()
        guard expiryDate > now else { return "Expired" }
        let diff = expiryDate.timeIntervalSince(now)
        let days    = Int(diff) / 86400
        let hours   = (Int(diff) % 86400) / 3600
        let minutes = (Int(diff) % 3600) / 60
        if days > 0 {
            return "\(days)d \(hours)h \(minutes)m"
        } else if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            let secs = Int(diff) % 60
            return "\(minutes)m \(secs)s"
        }
    }
}

// MARK: - Errors

enum LicenseError: LocalizedError {
    case invalidKey
    case networkError
    case serverError(Int)
    case deviceMismatch
    case expired

    var errorDescription: String? {
        switch self {
        case .invalidKey:         return "Invalid or expired key"
        case .networkError:       return "Network error — check your connection"
        case .serverError(let c): return "Server error (\(c))"
        case .deviceMismatch:     return "Key is bound to another device"
        case .expired:            return "License key has expired"
        }
    }
}
