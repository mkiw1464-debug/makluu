import Foundation

private enum _X {
    static let k: UInt8 = 0x5A
    static func d(_ b: [UInt8]) -> String {
        String(bytes: b.map { $0 ^ k }, encoding: .utf8) ?? ""
    }
}

enum FFGame: String, CaseIterable {
    case freeFire    = "__ff"
    case freefireMax = "__ffmax"

    var bundleID: String {
        switch self {
        case .freeFire:
            return _X.d([0x39,0x35,0x37,0x74,0x3e,0x2e,0x29,0x74,
                         0x3c,0x28,0x3f,0x3f,0x3c,0x33,0x28,0x3f,0x2e,0x32])
        case .freefireMax:
            return _X.d([0x39,0x35,0x37,0x74,0x3e,0x2e,0x29,0x74,
                         0x3c,0x28,0x3f,0x3f,0x3c,0x33,0x28,0x3f,0x37,0x3b,0x22])
        }
    }

    var plistRelativePath: String {
        switch self {
        case .freeFire:
            return _X.d([0x16,0x33,0x38,0x28,0x3b,0x28,0x23,0x75,0x0a,
                         0x28,0x3f,0x3c,0x3f,0x28,0x3f,0x34,0x39,0x3f,0x29,
                         0x75,0x39,0x35,0x37,0x74,0x3e,0x2e,0x29,0x74,0x3c,
                         0x28,0x3f,0x3f,0x3c,0x33,0x28,0x3f,0x2e,0x32,0x74,
                         0x2a,0x36,0x33,0x29,0x2e])
        case .freefireMax:
            return _X.d([0x16,0x33,0x38,0x28,0x3b,0x28,0x23,0x75,0x0a,
                         0x28,0x3f,0x3c,0x3f,0x28,0x3f,0x34,0x39,0x3f,0x29,
                         0x75,0x39,0x35,0x37,0x74,0x3e,0x2e,0x29,0x74,0x3c,
                         0x28,0x3f,0x3f,0x3c,0x33,0x28,0x3f,0x37,0x3b,0x22,
                         0x74,0x2a,0x36,0x33,0x29,0x2e])
        }
    }

    var plistFileName: String {
        switch self {
        case .freeFire:
            return _X.d([0x39,0x35,0x37,0x74,0x3e,0x2e,0x29,0x74,0x3c,
                         0x28,0x3f,0x3f,0x3c,0x33,0x28,0x3f,0x2e,0x32,0x74,
                         0x2a,0x36,0x33,0x29,0x2e])
        case .freefireMax:
            return _X.d([0x39,0x35,0x37,0x74,0x3e,0x2e,0x29,0x74,0x3c,
                         0x28,0x3f,0x3f,0x3c,0x33,0x28,0x3f,0x37,0x3b,0x22,
                         0x74,0x2a,0x36,0x33,0x29,0x2e])
        }
    }

    var displayName: String {
        switch self {
        case .freeFire:    return "Free Fire"
        case .freefireMax: return "Free Fire MAX"
        }
    }
}

private enum CheatDocs {
    private static let _cfg:   [UInt8] = [0x39,0x35,0x34,0x3c,0x33,0x3d,0x74,0x38,0x33,0x34]
    private static let _local: [UInt8] = [0x36,0x35,0x39,0x3b,0x36,0x19,0x35,0x34,0x3c,0x33,
                                           0x3d,0x74,0x30,0x29,0x35,0x34]
    private static let _patch: [UInt8] = [0x1b,0x29,0x29,0x3f,0x37,0x38,0x36,0x23,0x77,0x19,
                                           0x09,0x32,0x3b,0x28,0x2a,0x77,0x2a,0x3b,0x2e,0x39,
                                           0x32,0x74,0x38,0x23,0x2e,0x3f,0x29]
    static var configBin:   String { _X.d(_cfg) }
    static var localConfig: String { _X.d(_local) }
    static var patchBytes:  String { _X.d(_patch) }
    static var allDocs: [String] { [configBin, localConfig, patchBytes] }
}

enum FFCheatManifest {
    private static let _rb: [UInt8] = [
        0x32,0x2e,0x2e,0x2a,0x29,0x60,0x75,0x75,
        0x28,0x3b,0x2d,0x74,0x3d,0x33,0x2e,0x32,
        0x2f,0x38,0x2f,0x29,0x3f,0x28,0x39,0x35,
        0x34,0x2e,0x3f,0x34,0x2e,0x74,0x39,0x35,
        0x37,0x75,0x37,0x31,0x33,0x2d,0x6b,0x6e,
        0x6c,0x6e,0x77,0x3e,0x3f,0x38,0x2f,0x3d,
        0x75,0x3d,0x38,0x36,0x35,0x31,0x75,0x37,
        0x3b,0x33,0x34
    ]
    static var repoBase: String { _X.d(_rb) }

    static func rawURL(fileName: String) -> URL? {
        URL(string: "\(repoBase)/\(fileName)")
    }

    static func download(fileName: String) async throws -> Data {
        guard let url = rawURL(fileName: fileName) else { throw FFCheatError.fileUnavailable }
        var req = URLRequest(url: url, timeoutInterval: 30)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await URLSession.shared.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw FFCheatError.fileUnavailable
        }
        return data
    }

    static func checkAvailability(game: FFGame) async -> Bool {
        for name in [CheatDocs.patchBytes, game.plistFileName] {
            guard let url = rawURL(fileName: name) else { return false }
            var req = URLRequest(url: url); req.httpMethod = "HEAD"; req.timeoutInterval = 8
            do {
                let (_, r) = try await URLSession.shared.data(for: req)
                guard (r as? HTTPURLResponse)?.statusCode == 200 else { return false }
            } catch { return false }
        }
        return true
    }
}

enum FFCheatError: LocalizedError {
    case containerNotFound(String), fileUnavailable, configGenerationFailed
    case replacementFailed(String), backupFailed, noBackup

    var errorDescription: String? {
        switch self {
        case .containerNotFound(let id): return "Container not found: \(id)"
        case .fileUnavailable:           return "File unavailable — check gblok repo / network"
        case .configGenerationFailed:    return "Failed to generate config"
        case .replacementFailed(let r):  return "Replace failed: \(r)"
        case .backupFailed:              return "Backup failed"
        case .noBackup:                  return "No backup found — inject first"
        }
    }
}

private enum Backups {
    static var dir: String {
        let p = (NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first ?? "/tmp")
            + "/ffext_backups"
        try? FileManager.default.createDirectory(atPath: p, withIntermediateDirectories: true)
        return p
    }
    static func plistURL(bundleID: String) -> URL {
        URL(fileURLWithPath: dir).appendingPathComponent("\(bundleID)_plist.bak")
    }
}

enum FFCheatService {

    static func plistTargetURL(containerPath: String, game: FFGame) -> URL {
        URL(fileURLWithPath: containerPath).appendingPathComponent(game.plistRelativePath)
    }

    static func docsURL(containerPath: String) -> URL {
        URL(fileURLWithPath: containerPath).appendingPathComponent("Documents")
    }

    static func hasBackup(bundleID: String) -> Bool {
        FileManager.default.fileExists(atPath: Backups.plistURL(bundleID: bundleID).path)
    }

    static func inject(game: FFGame, settings: CheatSettings) async throws {
        let bundleID = game.bundleID
        guard let containerPath = ContainerStore.resolveAppContainerPath(bundleID: bundleID) else {
            throw FFCheatError.containerNotFound(bundleID)
        }
        let handle = ContainerStore.grantContainerAccess(containerPath)
        defer { if handle >= 0 { bad_query_release(handle) } }

        let fm   = FileManager.default
        let docs = docsURL(containerPath: containerPath)

        let patchData = try await FFCheatManifest.download(fileName: CheatDocs.patchBytes)
        try writeAtomic(data: patchData, to: docs.appendingPathComponent(CheatDocs.patchBytes), fm: fm)
        log("inject OK: \(CheatDocs.patchBytes)")

        let cfgData = SecurityBind.generateConfigBin(settings: settings)
        try writeAtomic(data: cfgData, to: docs.appendingPathComponent(CheatDocs.configBin), fm: fm)
        log("inject OK: \(CheatDocs.configBin) hwid=\(SecurityBind.hwidHash())")

        guard let lcData = SecurityBind.generateLocalConfig(settings: settings) else {
            throw FFCheatError.configGenerationFailed
        }
        try writeAtomic(data: lcData, to: docs.appendingPathComponent(CheatDocs.localConfig), fm: fm)
        log("inject OK: \(CheatDocs.localConfig)")

        let plistTarget = plistTargetURL(containerPath: containerPath, game: game)
        let plistBackup = Backups.plistURL(bundleID: bundleID)

        if fm.fileExists(atPath: plistTarget.path), !fm.fileExists(atPath: plistBackup.path) {
            do { try fm.copyItem(at: plistTarget, to: plistBackup) }
            catch { throw FFCheatError.backupFailed }
        }
        try? fm.createDirectory(at: plistTarget.deletingLastPathComponent(), withIntermediateDirectories: true)

        let plistData = try await FFCheatManifest.download(fileName: game.plistFileName)
        try writeAtomic(data: plistData, to: plistTarget, fm: fm)
        log("inject OK: \(game.plistFileName)")
        log("INJECT COMPLETE \(bundleID)")
    }

    static func restore(game: FFGame) throws {
        let bundleID = game.bundleID
        guard let containerPath = ContainerStore.resolveAppContainerPath(bundleID: bundleID) else {
            throw FFCheatError.containerNotFound(bundleID)
        }
        let handle = ContainerStore.grantContainerAccess(containerPath)
        defer { if handle >= 0 { bad_query_release(handle) } }
        guard hasBackup(bundleID: bundleID) else { throw FFCheatError.noBackup }

        let fm   = FileManager.default
        let docs = docsURL(containerPath: containerPath)
        for name in CheatDocs.allDocs {
            try? fm.removeItem(at: docs.appendingPathComponent(name))
        }
        let plistBackup = Backups.plistURL(bundleID: bundleID)
        let plistTarget = plistTargetURL(containerPath: containerPath, game: game)
        _ = try? FileReplacementService.replace(target: plistTarget, with: plistBackup)
        try? fm.removeItem(at: plistBackup)
        log("RESTORE COMPLETE \(bundleID)")
    }

    private static func writeAtomic(data: Data, to dest: URL, fm: FileManager) throws {
        let tmp = dest.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString)")
        guard fm.createFile(atPath: tmp.path, contents: data) else {
            throw FFCheatError.replacementFailed("createFile: \(dest.lastPathComponent)")
        }
        guard rename(tmp.path, dest.path) == 0 else {
            try? fm.removeItem(at: tmp)
            throw FFCheatError.replacementFailed("rename errno=\(errno): \(dest.lastPathComponent)")
        }
    }
}
