import Foundation

// MARK: - PlistGenerator
//
// Generates a binary plist (bplist00) from scratch containing
// PlayerPrefs values for Free Fire.
//
// On iOS, Unity PlayerPrefs stores ALL values in:
//   Library/Preferences/com.dts.freefireth.plist (or freefiremax)
//
// The Assembly-CSharp-patch reads these via PlayerPrefs.GetFloat/GetInt
// to activate each cheat feature. We generate this plist fresh
// based on the user's toggle settings — zero leaked content.

enum PlistGenerator {

    // MARK: - Generate plist data from settings

    static func generate(settings: CheatSettings, game: FFGame) -> Data {
        let aimbotOn = settings.aimbot || settings.aimSilent
        let anyESP   = settings.espBox || settings.espLine || settings.espHealth
                    || settings.espName || settings.espDistance || settings.espSkeleton

        // Build key-value dictionary with ALL feature PlayerPrefs
        var kv: [(String, BPValue)] = []

        // ── Aimbot ───────────────────────────────────────────────────────────
        kv.append(("__aa",    .int(aimbotOn ? 1 : 0)))
        kv.append(("__lhok",  .int(aimbotOn ? 1 : 0)))
        // Spatial coordinates — fixed values, only inject when aimbot on
        kv.append(("__lhx",   .int(aimbotOn ? 7184 : 0)))
        kv.append(("__lhy",   .int(aimbotOn ? 1269 : 0)))
        kv.append(("__lhz",   .int(aimbotOn ? 1639 : 0)))
        // FOV radius = aimbot lock radius (shared with FOV circle)
        kv.append(("__q17",   .int(settings.fovRadius)))
        // Aimbot lock speed / pull strength
        kv.append(("__q18",   .int(settings.aimbotStrength)))

        // ── AimSilent ────────────────────────────────────────────────────────
        kv.append(("__swep",  .int(settings.aimSilent ? 1   : 0)))
        kv.append(("__swpf",  .int(settings.aimSilent ? 975 : 0)))

        // ── Speed hack ───────────────────────────────────────────────────────
        kv.append(("__mrf",   .int(settings.speedHack ? 965 : 0)))
        kv.append(("__spf",   .int(settings.speedHack ? 973 : 0)))
        kv.append(("__q20",   .int(settings.speedHack ? 5   : 0)))  // multiplier

        // ── Bullet speed / fire rate ─────────────────────────────────────────
        kv.append(("__q19",   .int(settings.bulletSpeed ? 10 : 1)))

        // ── ESP master ───────────────────────────────────────────────────────
        kv.append(("__espon", .int(anyESP ? 1  : 0)))
        kv.append(("__espm",  .int(anyESP ? 31 : 0)))

        // ── ESP individual ───────────────────────────────────────────────────
        kv.append(("__ebox",      .int(settings.espBox      ? 1   : 0)))
        kv.append(("__ename",     .int(settings.espName     ? 1   : 0)))
        kv.append(("__ehp",       .int(settings.espHealth   ? 1   : 0)))
        kv.append(("__eline",     .int(settings.espLine     ? 1   : 0)))
        kv.append(("__edist",     .int(settings.espDistance ? 120 : 0)))
        kv.append(("__edistance", .int(settings.espDistance ? 1   : 0)))
        kv.append(("__efull",     .int(settings.espSkeleton ? 1   : 0)))

        // ── Enemy counter ────────────────────────────────────────────────────
        kv.append(("__hot",  .int(settings.enemyCounter ? 31                    : 0)))
        kv.append(("__q21",  .int(settings.enemyCounter ? settings.enemyDistance : 0)))

        // ── FPS unlock ───────────────────────────────────────────────────────
        // The patch's SetHighFPSSetting hook activates automatically.
        // GameSettingData.FrameRate pref forces 144fps when set.
        if settings.fps144 {
            kv.append(("GameSettingData.FrameRate", .int(144)))
            kv.append(("EHighFPS",                  .int(4)))    // enum 4 = 144fps
        }

        return BPlistWriter.write(dict: kv)
    }
}

// MARK: - Binary Plist (bplist00) Writer
//
// Writes a minimal bplist00 containing only integer and string objects.
// Format: magic(8) + objects + offset_table + trailer(32)

enum BPValue {
    case int(Int)
    case string(String)
    case real(Double)
}

enum BPlistWriter {

    static func write(dict: [(String, BPValue)]) -> Data {
        // Objects: keys + values interleaved, then root dict
        // Total objects = keys.count + values.count + 1 (root dict)
        var objects: [BPValue] = []

        // Add all key strings first, then all values
        for (k, _) in dict { objects.append(.string(k)) }
        for (_, v) in dict { objects.append(v) }

        let numObjects = objects.count + 1      // +1 for root dict object
        let refSize    = refSizeFor(numObjects)

        // Encode each object
        var objectData: [Data] = objects.map { encode($0) }
        // Root dict object (added last)
        objectData.append(encodeDict(count: dict.count, refSize: refSize))

        // Build offset table
        var offsets: [Int] = []
        var currentOffset  = 8  // after magic "bplist00"

        for od in objectData {
            offsets.append(currentOffset)
            currentOffset += od.count
        }
        // Root dict index is last
        let rootIndex = numObjects - 1
        let offsetTableStart = currentOffset

        // Assemble
        var data = Data()
        data.append(contentsOf: Array("bplist00".utf8))
        for od in objectData { data.append(od) }

        // Offset table
        let offSize = offSizeFor(offsetTableStart + numObjects * refSize + 32)
        for off in offsets { data.append(encodeInt(off, size: offSize)) }

        // Trailer (32 bytes)
        data.append(contentsOf: [UInt8](repeating: 0, count: 6))  // padding
        data.append(UInt8(offSize))
        data.append(UInt8(refSize))
        data.append(encodeInt(numObjects, size: 8))
        data.append(encodeInt(rootIndex,  size: 8))
        data.append(encodeInt(offsetTableStart, size: 8))

        // Now fix the root dict — it needs ref indices for keys and values
        // We need to reconstruct with actual ref indices embedded
        return buildFull(dict: dict, refSize: refSize)
    }

    // MARK: - Full build with proper ref indices

    private static func buildFull(dict: [(String, BPValue)], refSize: Int) -> Data {
        let keyCount = dict.count
        let numObjects = dict.count * 2 + 1  // keys + values + root dict
        let refSz = refSizeFor(numObjects)

        // Key objects: indices 0..<keyCount
        // Value objects: indices keyCount..<keyCount*2
        // Root dict: index keyCount*2

        var objectDatas: [Data] = []
        for (k, _) in dict { objectDatas.append(encode(.string(k))) }
        for (_, v) in dict { objectDatas.append(encode(v)) }

        // Root dict: marker + count + key_refs + val_refs
        var rootDict = Data()
        let marker = buildDictMarker(count: keyCount)
        rootDict.append(contentsOf: marker)
        for i in 0..<keyCount       { rootDict.append(encodeRef(i,           size: refSz)) }
        for i in 0..<keyCount       { rootDict.append(encodeRef(keyCount+i,  size: refSz)) }
        objectDatas.append(rootDict)

        // Build offset table
        var offsets: [Int] = []
        var cur = 8
        for od in objectDatas { offsets.append(cur); cur += od.count }

        let offsetTableStart = cur
        let offSz = offSizeFor(offsetTableStart + numObjects * refSz + 32)

        var data = Data()
        data.append(contentsOf: Array("bplist00".utf8))
        for od in objectDatas { data.append(od) }

        for off in offsets { data.append(encodeInt(off, size: offSz)) }

        // Trailer
        data.append(contentsOf: [UInt8](repeating: 0, count: 6))
        data.append(UInt8(offSz))
        data.append(UInt8(refSz))
        data.append(encodeInt(numObjects, size: 8))
        data.append(encodeInt(numObjects - 1, size: 8))  // root = last object
        data.append(encodeInt(offsetTableStart, size: 8))

        return data
    }

    // MARK: - Object encoders

    private static func encode(_ v: BPValue) -> Data {
        switch v {
        case .string(let s):
            let bytes = Array(s.utf8)
            var d = Data()
            if bytes.count < 15 {
                d.append(UInt8(0x50 | bytes.count))
            } else {
                d.append(0x5F)
                d.append(contentsOf: encodeIntObject(bytes.count))
            }
            d.append(contentsOf: bytes)
            return d

        case .int(let i):
            if i == 0 { var d = Data(); d.append(0x10); d.append(0x00); return d }
            if i < 256 {
                var d = Data(); d.append(0x10); d.append(UInt8(i)); return d
            }
            if i < 65536 {
                var d = Data(); d.append(0x11)
                d.append(UInt8((i >> 8) & 0xFF)); d.append(UInt8(i & 0xFF)); return d
            }
            var d = Data(); d.append(0x12)
            d.append(UInt8((i >> 24) & 0xFF)); d.append(UInt8((i >> 16) & 0xFF))
            d.append(UInt8((i >> 8)  & 0xFF)); d.append(UInt8(i & 0xFF)); return d

        case .real(let r):
            var d = Data(); d.append(0x23)
            var bits = r.bitPattern
            d.append(contentsOf: withUnsafeBytes(of: &bits) { Array($0).reversed() })
            return d
        }
    }

    private static func encodeIntObject(_ v: Int) -> Data {
        var d = Data()
        if v < 256       { d.append(0x10); d.append(UInt8(v)) }
        else if v < 65536 {
            d.append(0x11)
            d.append(UInt8((v >> 8) & 0xFF)); d.append(UInt8(v & 0xFF))
        } else {
            d.append(0x12)
            d.append(UInt8((v >> 24) & 0xFF)); d.append(UInt8((v >> 16) & 0xFF))
            d.append(UInt8((v >> 8) & 0xFF));  d.append(UInt8(v & 0xFF))
        }
        return d
    }

    private static func buildDictMarker(count: Int) -> [UInt8] {
        if count < 15 { return [UInt8(0xD0 | count)] }
        var r: [UInt8] = [0xDF]
        r.append(contentsOf: Array(encodeIntObject(count)))
        return r
    }

    // MARK: - Helpers

    private static func encodeRef(_ index: Int, size: Int) -> Data {
        encodeInt(index, size: size)
    }

    private static func encodeInt(_ v: Int, size: Int) -> Data {
        var d = Data()
        for shift in stride(from: (size-1)*8, through: 0, by: -8) {
            d.append(UInt8((v >> shift) & 0xFF))
        }
        return d
    }

    private static func encodeDict(count: Int, refSize: Int) -> Data { Data() }

    private static func refSizeFor(_ count: Int) -> Int {
        if count < 256 { return 1 }
        if count < 65536 { return 2 }
        return 4
    }

    private static func offSizeFor(_ maxOff: Int) -> Int {
        if maxOff < 256 { return 1 }
        if maxOff < 65536 { return 2 }
        if maxOff < 16777216 { return 3 }
        return 4
    }
}

// MARK: - Data extension for appending Data

private extension Data {
    mutating func append(_ other: Data) {
        self.append(contentsOf: other)
    }
}
