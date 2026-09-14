import Foundation

// MARK: - PlistGenerator
//
// Generates binary plist (bplist00) from scratch.
// Controls ALL features via PlayerPrefs on iOS Unity.
//
// Two key types:
//   Integer keys  — __aa, __spf, __q17 etc (feature flags + values)
//   String keys   — MN_CFG, MN_AIM_FRAME (10/16-char bitstrings read by patch
//                   via PlayerPrefs.GetString to enable speed/fps/fire rate)

enum PlistGenerator {

    static func generate(settings: CheatSettings, game: FFGame) -> Data {
        let aimbotOn = settings.aimbot || settings.aimSilent
        let anyESP   = settings.espBox || settings.espLine || settings.espHealth
                    || settings.espName || settings.espDistance || settings.espSkeleton

        var kv: [(String, BPValue)] = []

        // ── Integer keys ──────────────────────────────────────────────────────
        kv += [
            ("__aa",    .int(aimbotOn ? 1 : 0)),
            ("__lhok",  .int(aimbotOn ? 1 : 0)),
            ("__lhx",   .int(aimbotOn ? 7184 : 0)),
            ("__lhy",   .int(aimbotOn ? 1269 : 0)),
            ("__lhz",   .int(aimbotOn ? 1639 : 0)),
            ("__q17",   .int(settings.fovRadius)),
            ("__q18",   .int(settings.aimbotStrength)),
            ("__swep",  .int(settings.aimSilent ? 1   : 0)),
            ("__swpf",  .int(settings.aimSilent ? 975 : 0)),
            ("__mrf",   .int(settings.speedHack ? 965 : 0)),
            ("__spf",   .int(settings.speedHack ? 973 : 0)),
            ("__q20",   .int(settings.speedHack ? 5   : 0)),
            ("__q19",   .int(settings.bulletSpeed ? 10 : 1)),
            ("__espon", .int(anyESP ? 1  : 0)),
            ("__espm",  .int(anyESP ? 31 : 0)),
            ("__ebox",  .int(settings.espBox      ? 1   : 0)),
            ("__ename", .int(settings.espName     ? 1   : 0)),
            ("__ehp",   .int(settings.espHealth   ? 1   : 0)),
            ("__eline", .int(settings.espLine     ? 1   : 0)),
            ("__edist", .int(settings.espDistance ? 120 : 0)),
            ("__edistance", .int(settings.espDistance ? 1 : 0)),
            ("__efull", .int(settings.espSkeleton ? 1 : 0)),
            ("__hot",   .int(settings.enemyCounter ? 31 : 0)),
            ("__q21",   .int(settings.enemyCounter ? settings.enemyDistance : 0)),
        ]

        if settings.fps144 {
            kv.append(("GameSettingData.FrameRate", .int(144)))
            kv.append(("EHighFPS", .int(4)))
        }

        // ── String keys (MN_CFG bitstrings) ──────────────────────────────────
        // MN_CFG: 10-char string, each char '0'/'1' per feature
        // [0]=aimframe [1]=aimbest [2]=speed [3]=firate [4]=fps
        // [5]=esp      [6]=target  [7]=silent [8]=counter [9]=misc
        var cfg = [Character](repeating: "0", count: 10)
        if aimbotOn             { cfg[0] = "1"; cfg[1] = "1"; cfg[6] = "1" }
        if settings.speedHack   { cfg[2] = "1" }
        if settings.bulletSpeed { cfg[3] = "1" }
        if settings.fps144      { cfg[4] = "1" }
        if anyESP               { cfg[5] = "1" }
        if settings.aimSilent   { cfg[7] = "1" }
        if settings.enemyCounter { cfg[8] = "1" }
        kv.append(("MN_CFG", .string(String(cfg))))

        let aimStr = aimbotOn ? "1111111111111111" : "0000000000000000"
        kv.append(("MN_AIM_FRAME", .string(aimStr)))
        kv.append(("MN_AIM_BEST",  .string(aimbotOn ? "11111111111" : "00000000000")))
        kv.append(("MN_AIM_TARGET", .string(aimbotOn ? String(settings.aimbotTargetRaw + 1) : "0")))

        return BPlistWriter.write(dict: kv)
    }
}

// MARK: - Binary Plist Writer

enum BPValue {
    case int(Int)
    case string(String)
}

enum BPlistWriter {

    static func write(dict: [(String, BPValue)]) -> Data {
        let n = dict.count
        let numObjects = n * 2 + 1
        let refSz = refSize(numObjects)

        var allObjects = [[UInt8]]()
        for (k, _) in dict { allObjects.append(encodeString(k)) }
        for (_, v) in dict { allObjects.append(encodeValue(v)) }

        // Root dict marker
        var rootDict = [UInt8]()
        if n < 15 {
            rootDict.append(UInt8(0xD0 | n))
        } else {
            rootDict.append(0xDF)
            rootDict += encodeIntObj(n)
        }
        for i in 0..<n { rootDict += encodeRef(i,     sz: refSz) }
        for i in 0..<n { rootDict += encodeRef(n + i, sz: refSz) }
        allObjects.append(rootDict)

        // Compute offsets
        var offsets = [Int]()
        var cur = 8
        for obj in allObjects { offsets.append(cur); cur += obj.count }
        let offsetTableStart = cur
        let offSz = offSize(offsetTableStart + numObjects * refSz + 32)

        // Assemble
        var data = Data("bplist00".utf8)
        for obj in allObjects { data.append(contentsOf: obj) }
        for off in offsets    { data.append(contentsOf: encodeInt(off, sz: offSz)) }
        data.append(contentsOf: [UInt8](repeating: 0, count: 6))
        data.append(UInt8(offSz))
        data.append(UInt8(refSz))
        data.append(contentsOf: encodeInt(numObjects,       sz: 8))
        data.append(contentsOf: encodeInt(numObjects - 1,   sz: 8))
        data.append(contentsOf: encodeInt(offsetTableStart, sz: 8))
        return data
    }

    // MARK: - Encoders

    private static func encodeString(_ s: String) -> [UInt8] {
        let bytes = Array(s.utf8)
        if bytes.count < 15 {
            return [UInt8(0x50 | bytes.count)] + bytes
        }
        return [0x5F] + encodeIntObj(bytes.count) + bytes
    }

    private static func encodeValue(_ v: BPValue) -> [UInt8] {
        switch v {
        case .string(let s): return encodeString(s)
        case .int(let i):
            if i <= 0    { return [0x10, 0x00] }
            if i < 256   { return [0x10, UInt8(i)] }
            if i < 65536 { return [0x11, UInt8((i >> 8) & 0xFF), UInt8(i & 0xFF)] }
            return [0x12,
                    UInt8((i >> 24) & 0xFF), UInt8((i >> 16) & 0xFF),
                    UInt8((i >> 8)  & 0xFF), UInt8(i & 0xFF)]
        }
    }

    private static func encodeIntObj(_ v: Int) -> [UInt8] {
        if v < 256   { return [0x10, UInt8(v)] }
        if v < 65536 { return [0x11, UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)] }
        return [0x12, UInt8((v>>24)&0xFF), UInt8((v>>16)&0xFF),
                      UInt8((v>>8) &0xFF), UInt8(v&0xFF)]
    }

    private static func encodeRef(_ i: Int, sz: Int) -> [UInt8] { encodeInt(i, sz: sz) }

    private static func encodeInt(_ v: Int, sz: Int) -> [UInt8] {
        var d = [UInt8]()
        for shift in stride(from: (sz - 1) * 8, through: 0, by: -8) {
            d.append(UInt8((v >> shift) & 0xFF))
        }
        return d
    }

    private static func refSize(_ n: Int) -> Int { n < 256 ? 1 : n < 65536 ? 2 : 4 }
    private static func offSize(_ n: Int) -> Int {
        n < 256 ? 1 : n < 65536 ? 2 : n < 16777216 ? 3 : 4
    }
}
