import Foundation

// MARK: - PlistGenerator
//
// Generates binary plist (bplist00) from scratch with ALL PlayerPrefs values
// needed by Assembly-CSharp-patch to activate features on iOS.
//
// Three types of keys in the plist:
//   1. Integer keys (__aa, __spf, __q17, etc) — basic feature flags + values
//   2. String keys (MN_CFG, MN_AIM_FRAME, etc) — 10/16-char feature bitstrings
//      read by IL patch via PlayerPrefs.GetString() to control speed/fps/aim
//   3. Game settings (GameSettingData.FrameRate) — direct game settings

enum PlistGenerator {

    // MARK: - Generate

    static func generate(settings: CheatSettings, game: FFGame) -> Data {
        let aimbotOn = settings.aimbot || settings.aimSilent
        let anyESP   = settings.espBox || settings.espLine || settings.espHealth
                    || settings.espName || settings.espDistance || settings.espSkeleton

        var kv: [(String, BPValue)] = []

        // ── INTEGER KEYS ──────────────────────────────────────────────────────

        // Aimbot
        kv.append(("__aa",    .int(aimbotOn ? 1 : 0)))
        kv.append(("__lhok",  .int(aimbotOn ? 1 : 0)))
        kv.append(("__lhx",   .int(aimbotOn ? 7184 : 0)))
        kv.append(("__lhy",   .int(aimbotOn ? 1269 : 0)))
        kv.append(("__lhz",   .int(aimbotOn ? 1639 : 0)))
        kv.append(("__q17",   .int(settings.fovRadius)))
        kv.append(("__q18",   .int(settings.aimbotStrength)))

        // AimSilent
        kv.append(("__swep",  .int(settings.aimSilent ? 1   : 0)))
        kv.append(("__swpf",  .int(settings.aimSilent ? 975 : 0)))

        // Speed
        kv.append(("__mrf",   .int(settings.speedHack ? 965 : 0)))
        kv.append(("__spf",   .int(settings.speedHack ? 973 : 0)))
        kv.append(("__q20",   .int(settings.speedHack ? 5   : 0)))

        // Fire rate
        kv.append(("__q19",   .int(settings.bulletSpeed ? 10 : 1)))

        // ESP
        kv.append(("__espon", .int(anyESP ? 1  : 0)))
        kv.append(("__espm",  .int(anyESP ? 31 : 0)))
        kv.append(("__ebox",  .int(settings.espBox      ? 1   : 0)))
        kv.append(("__ename", .int(settings.espName     ? 1   : 0)))
        kv.append(("__ehp",   .int(settings.espHealth   ? 1   : 0)))
        kv.append(("__eline", .int(settings.espLine     ? 1   : 0)))
        kv.append(("__edist", .int(settings.espDistance ? 120 : 0)))
        kv.append(("__edistance", .int(settings.espDistance ? 1 : 0)))
        kv.append(("__efull", .int(settings.espSkeleton ? 1   : 0)))

        // Enemy counter
        kv.append(("__hot",   .int(settings.enemyCounter ? 31                    : 0)))
        kv.append(("__q21",   .int(settings.enemyCounter ? settings.enemyDistance : 0)))

        // FPS
        if settings.fps144 {
            kv.append(("GameSettingData.FrameRate", .int(144)))
            kv.append(("EHighFPS",                  .int(4)))
        }

        // ── STRING KEYS (MN_CFG bitstrings) ──────────────────────────────────
        //
        // MN_CFG = 10-char string, each char '0' or '1'
        // Read by patch via PlayerPrefs.GetString("MN_CFG")
        // Char positions control: speed/firate/fps/aimbot via get_Chars indexing
        // Set ALL to '1' when feature is on to ensure patch activates it.
        //
        // Char layout (reversed from config.bin order):
        // [0]=aimframe [1]=aimbest [2]=speed [3]=firate [4]=fps
        // [5]=esp [6]=aimtarget [7]=silentaim [8]=counter [9]=misc

        var mnCfg = Array(repeating: Character("0"), count: 10)
        if aimbotOn           { mnCfg[0] = "1"; mnCfg[1] = "1"; mnCfg[6] = "1" }
        if settings.speedHack { mnCfg[2] = "1" }
        if settings.bulletSpeed { mnCfg[3] = "1" }
        if settings.fps144    { mnCfg[4] = "1" }
        if anyESP             { mnCfg[5] = "1" }
        if settings.aimSilent { mnCfg[7] = "1" }
        if settings.enemyCounter { mnCfg[8] = "1" }
        kv.append(("MN_CFG", .string(String(mnCfg))))

        // MN_AIM_FRAME = 16-char bitstring for aimbot frame configuration
        var mnAimFrame = Array(repeating: Character("0"), count: 16)
        if aimbotOn { mnAimFrame = Array(repeating: Character("1"), count: 16) }
        kv.append(("MN_AIM_FRAME", .string(String(mnAimFrame))))

        // MN_AIM_BEST = 11-char target selection config
        var mnAimBest = Array(repeating: Character("0"), count: 11)
        if aimbotOn { mnAimBest = Array(repeating: Character("1"), count: 11) }
        kv.append(("MN_AIM_BEST", .string(String(mnAimBest))))

        // MN_AIM_TARGET = target type (head=1, neck=2, body=3)
        let aimTargetChar = String(settings.aimbotTargetRaw + 1)
        kv.append(("MN_AIM_TARGET", .string(aimbotOn ? aimTargetChar : "0")))

        return BPlistWriter.write(dict: kv)
    }
}

// MARK: - Binary Plist (bplist00) Writer

enum BPValue {
    case int(Int)
    case string(String)
    case real(Double)
}

enum BPlistWriter {

    static func write(dict: [(String, BPValue)]) -> Data {
        buildFull(dict: dict)
    }

    private static func buildFull(dict: [(String, BPValue)]) -> Data {
        let n = dict.count
        let numObjects = n * 2 + 1
        let refSz = refSizeFor(numObjects)

        var objectDatas: [Data] = []
        for (k, _) in dict { objectDatas.append(encode(.string(k))) }
        for (_, v) in dict { objectDatas.append(encode(v)) }

        // Root dict
        var rootDict = Data()
        let marker: [UInt8] = n < 15 ? [UInt8(0xD0 | n)] : {
            var m: [UInt8] = [0xDF]
            m.append(contentsOf: encodeIntObject(n))
            return m
        }()
        rootDict.append(contentsOf: marker)
        for i in 0..<n       { rootDict.append(contentsOf: encodeRef(i,       size: refSz)) }
        for i in 0..<n       { rootDict.append(contentsOf: encodeRef(n + i,   size: refSz)) }
        objectDatas.append(rootDict)

        var offsets: [Int] = []
        var cur = 8
        for od in objectDatas { offsets.append(cur); cur += od.count }
        let offsetTableStart = cur
        let offSz = offSizeFor(offsetTableStart + numObjects * refSz + 32)

        var data = Data()
        data.append(contentsOf: Array("bplist00".utf8))
        for od in objectDatas { data.append(contentsOf: od) }
        for off in offsets     { data.append(contentsOf: encodeInt(off, size: offSz)) }

        data.append(contentsOf: [UInt8](repeating: 0, count: 6))
        data.append(UInt8(offSz))
        data.append(UInt8(refSz))
        data.append(contentsOf: encodeInt(numObjects, size: 8))
        data.append(contentsOf: encodeInt(numObjects - 1, size: 8))
        data.append(contentsOf: encodeInt(offsetTableStart, size: 8))

        return data
    }

    private static func encode(_ v: BPValue) -> [UInt8] {
        switch v {
        case .string(let s):
            let bytes = Array(s.utf8)
            var d: [UInt8] = []
            if bytes.count < 15 {
                d.append(UInt8(0x50 | bytes.count))
            } else {
                d.append(0x5F)
                d.append(contentsOf: encodeIntObject(bytes.count))
            }
            d.append(contentsOf: bytes)
            return d

        case .int(let i):
            if i <= 0   { return [0x10, 0x00] }
            if i < 256  { return [0x10, UInt8(i)] }
            if i < 65536 {
                return [0x11, UInt8((i >> 8) & 0xFF), UInt8(i & 0xFF)]
            }
            return [0x12,
                    UInt8((i >> 24) & 0xFF), UInt8((i >> 16) & 0xFF),
                    UInt8((i >> 8)  & 0xFF), UInt8(i & 0xFF)]

        case .real(let r):
            var d: [UInt8] = [0x23]
            var bits = r.bitPattern
            d.append(contentsOf: withUnsafeBytes(of: &bits) { Array($0).reversed() })
            return d
        }
    }

    private static func encodeIntObject(_ v: Int) -> [UInt8] {
        if v < 256   { return [0x10, UInt8(v)] }
        if v < 65536 { return [0x11, UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)] }
        return [0x12, UInt8((v>>24)&0xFF), UInt8((v>>16)&0xFF),
                      UInt8((v>>8) &0xFF), UInt8(v&0xFF)]
    }

    private static func encodeRef(_ i: Int, size: Int) -> [UInt8] { encodeInt(i, size: size) }

    private static func encodeInt(_ v: Int, size: Int) -> [UInt8] {
        var d = [UInt8]()
        for shift in stride(from: (size - 1) * 8, through: 0, by: -8) {
            d.append(UInt8((v >> shift) & 0xFF))
        }
        return d
    }

    private static func refSizeFor(_ n: Int) -> Int { n < 256 ? 1 : n < 65536 ? 2 : 4 }
    private static func offSizeFor(_ n: Int) -> Int {
        n < 256 ? 1 : n < 65536 ? 2 : n < 16777216 ? 3 : 4
    }
}
