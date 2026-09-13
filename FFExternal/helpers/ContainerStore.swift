import Foundation
import Darwin

// MARK: - Models

struct InstalledApp: Identifiable, Hashable {
    let bundleID: String
    let containerPath: String
    var id: String { bundleID }
}

struct ContainerMetadata: Equatable {
    let bundleID: String
    let displayName: String
}

struct FileEntry: Identifiable, Hashable {
    let name: String
    let path: String
    let isDirectory: Bool
    let size: Int64
    var id: String { path }
}

// MARK: - ContainerStore (minimal — FF External only needs path resolution)

enum ContainerStore {
    static let appDataRoot = "/var/mobile/Containers/Data/Application"

    private static var shouldUseBadQuery: Bool {
        ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26
    }

    // MARK: - Public API

    /// Resolves the Data container path for a given bundle identifier.
    /// Uses MCM first, falls back to filesystem metadata scan.
    static func resolveAppContainerPath(bundleID: String) -> String? {
        var lookupError: NSString?
        if let path = MCMActivateContainerPath(2, bundleID, false, &lookupError),
           isApplicationContainerPath(path) {
            log("ffext: MCM resolved \(bundleID) -> \(path)")
            return path
        }
        let detail = lookupError.map(String.init) ?? "unavailable"
        log("ffext: MCM failed for \(bundleID) detail=\(detail), trying metadata scan")
        return resolveByMetadataScan(bundleID: bundleID)
    }

    static func isApplicationContainerPath(_ path: String) -> Bool {
        let canonicalRoot = canonical(appDataRoot)
        let canonicalPath = canonical(path)
        guard canonicalPath.hasPrefix(canonicalRoot + "/") else { return false }
        return UUID(uuidString: (canonicalPath as NSString).lastPathComponent) != nil
    }

    // MARK: - Filesystem access

    static func grantContainerAccess(_ containerPath: String) -> Int64 {
        guard shouldUseBadQuery else { return -1 }
        let clean = containerPath.hasSuffix("/") ? String(containerPath.dropLast()) : containerPath
        var pathC = clean.utf8CString.map { Int8($0) }
        return bad_query(&pathC, true, nil, false)
    }

    static func enumerateDirectories(path: String) -> [String] {
        let clean = path.hasSuffix("/") ? String(path.dropLast()) : path
        if let names = try? FileManager.default.contentsOfDirectory(atPath: clean), !names.isEmpty {
            return names.map { (clean as NSString).appendingPathComponent($0) }
        }
        var pathC = clean.utf8CString.map { Int8($0) }
        guard let result = bad_query_list(&pathC, 2_000_000) else { return [] }
        defer { free(result) }
        return String(cString: result).components(separatedBy: "\n").filter { !$0.isEmpty }
    }

    static func readContainerMetadata(containerPath: String) -> ContainerMetadata? {
        let metadataPath = (containerPath as NSString)
            .appendingPathComponent(".com.apple.mobile_container_manager.metadata.plist")
        var data: Data?
        if let fd = fopen(metadataPath, "r") {
            var buf = [UInt8](repeating: 0, count: 65536)
            var bytes: [UInt8] = []
            while true {
                let n = fread(&buf, 1, buf.count, fd)
                if n <= 0 { break }
                bytes.append(contentsOf: buf[0..<n])
            }
            fclose(fd)
            if !bytes.isEmpty { data = Data(bytes) }
        }
        if data == nil { data = try? Data(contentsOf: URL(fileURLWithPath: metadataPath)) }
        guard let validData = data,
              let plist = try? PropertyListSerialization.propertyList(from: validData, options: [], format: nil) as? [String: Any] else {
            return nil
        }
        let bundleID = plist["MCMMetadataIdentifier"] as? String ?? ""
        var displayName = ""
        if let info = plist["MCMMetadataInfo"] as? [String: Any] {
            displayName = (info["CFBundleDisplayName"] as? String)
                ?? (info["CFBundleName"] as? String) ?? ""
        }
        return ContainerMetadata(bundleID: bundleID, displayName: displayName)
    }

    static func listFiles(at path: String) -> [FileEntry] {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(atPath: path) else { return [] }
        var entries: [FileEntry] = []
        for item in items {
            if item.hasPrefix(".") { continue }
            let full = (path as NSString).appendingPathComponent(item)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: full, isDirectory: &isDir) else { continue }
            let size = isDir.boolValue ? 0 : ((try? fm.attributesOfItem(atPath: full)[.size] as? Int64) ?? 0)
            entries.append(FileEntry(name: item, path: full, isDirectory: isDir.boolValue, size: size))
        }
        return entries
    }

    // MARK: - Private

    private static func canonical(_ rawPath: String) -> String {
        var path = (rawPath as NSString).standardizingPath
        if path == "/var" || path.hasPrefix("/var/") {
            path = "/private" + path
        }
        while path.count > 1 && path.hasSuffix("/") { path.removeLast() }
        return path
    }

    private static func resolveByMetadataScan(bundleID: String) -> String? {
        if KernelExploit.requiresSandboxEscape, !KernelExploit.hasSandboxAccess() {
            log("ffext: metadata scan skipped — no sandbox access")
            return nil
        }
        let dirs = enumerateDirectories(path: appDataRoot)
        for dir in dirs {
            guard UUID(uuidString: (dir as NSString).lastPathComponent) != nil else { continue }
            guard let metadata = readContainerMetadata(containerPath: dir),
                  metadata.bundleID == bundleID else { continue }
            let path = canonical(dir)
            guard isApplicationContainerPath(path) else { continue }
            log("ffext: metadata scan resolved \(bundleID) -> \(path)")
            return path
        }
        return nil
    }
}
