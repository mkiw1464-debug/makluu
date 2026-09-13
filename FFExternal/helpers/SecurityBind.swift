import Foundation
import CryptoKit

// MARK: - SecurityBind
//
// FOV radius is the SINGLE SOURCE OF TRUTH for:
//   • The on-screen circle size
//   • Aimbot/AimSilent lock radius (__q17 in localConfig.json)
//   • Enemy counter detection radius (__q21)
//
// config.bin layout (46 bytes, sequential flags):
//   [0]  delete = 0x01
//   [1]  __aa   aimbot
//   [2]  __ebox ESP box
//   [3]  __espm ESP master
//   [4]  __cage 0x00
//   [5]  __cghp 0x00
//   [6]  __cgwas 0x78 fixed
//   [7]  __cgoff 0x00
//   [8]  __hot  enemy counter
//   [9]  __espon ESP on
//   [10] __camid 0x00
//   [11] __ehead ESP name/head
//   [12] __efull ESP skeleton
//   [13] __ehp  ESP health
//   [14] __eline ESP line
//   [15] __elag 0x00
//   [16] __moco 0x00
//   [17] __edist ESP distance
//   [18] __xray 0x00
//   [19] __xroff 0x00
//   [20] __mcwas 0x00
//   [21] __lhok aimbot hook
//   [22] __swep aimsilent
//   [23] __mrf  speed
//   [24-31] 0x00
//   [32] __spf  speed hack
//   [33] __spec 0x00
//   [34-43] 0x00
//   [44] __m   0x01
//   [45] __swpf aimsilent force

enum SecurityBind {

    // MARK: - HWID

    static func hwidHash() -> String {
        let data = Data(DeviceID.hwid.utf8)
        let dig  = SHA256.hash(data: data)
        return dig.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - config.bin (46 bytes)

    static func generateConfigBin(settings: CheatSettings) -> Data {
        var b = [UInt8](repeating: 0, count: 46)
        let on: UInt8 = 0x01

        b[0]  = 0x01
        b[6]  = 0x78
        b[44] = 0x01

        let aimbotOn = settings.aimbot || settings.aimSilent
        b[1]  = aimbotOn ? on : 0
        b[21] = aimbotOn ? on : 0
        b[22] = settings.aimSilent ? on : 0
        b[45] = settings.aimSilent ? on : 0

        b[8]  = settings.enemyCounter ? on : 0

        let anyESP = settings.espBox || settings.espLine || settings.espHealth
                  || settings.espName || settings.espDistance || settings.espSkeleton
        b[3]  = anyESP ? on : 0
        b[9]  = anyESP ? on : 0
        b[2]  = settings.espBox      ? on : 0
        b[11] = settings.espName     ? on : 0
        b[12] = settings.espSkeleton ? on : 0
        b[13] = settings.espHealth   ? on : 0
        b[14] = settings.espLine     ? on : 0
        b[17] = settings.espDistance ? on : 0

        b[23] = settings.speedHack ? on : 0
        b[32] = settings.speedHack ? on : 0

        return Data(b)
    }

    // MARK: - localConfig.json
    //
    // __q17 = FOV radius = aimbot lock radius
    // __q18 = aimbot strength (0-100)
    // These sync to the on-screen FOV circle.

    static func generateLocalConfig(settings: CheatSettings) -> Data? {
        let ts  = Int(Date().timeIntervalSince1970)
        let ttl = ts + 86400

        let aimbotOn = settings.aimbot || settings.aimSilent
        let anyESP   = settings.espBox || settings.espLine || settings.espHealth
                    || settings.espName || settings.espDistance || settings.espSkeleton

        // FOV radius is SHARED between circle, aimbot lock, and aimsilent sweep
        let fovRadius   = max(0, min(200, settings.fovRadius))
        let aimStrength = max(0, min(100, settings.aimbotStrength))

        // Aimbot spatial coords from working plist
        let lhx: Int = aimbotOn ? 7184 : 0
        let lhy: Int = aimbotOn ? 1269 : 0
        let lhz: Int = aimbotOn ? 1639 : 0

        let payload: [String: Any] = [
            "testCodePatch": true,

            // Aimbot
            "__aa":    aimbotOn ? 1 : 0,
            "__lhok":  aimbotOn ? 1 : 0,
            "__lhx":   lhx,
            "__lhy":   lhy,
            "__lhz":   lhz,

            // AimSilent
            "__swep":  settings.aimSilent ? 1   : 0,
            "__swpf":  settings.aimSilent ? 975 : 0,

            // Speed
            "__mrf":   settings.speedHack ? 965 : 0,
            "__spf":   settings.speedHack ? 973 : 0,
            "__spec":  0,

            // ESP
            "__espm":      anyESP ? 31 : 0,
            "__espon":     anyESP ? 1  : 0,
            "__ebox":      settings.espBox      ? 1   : 0,
            "__ename":     settings.espName     ? 1   : 0,
            "__ehp":       settings.espHealth   ? 1   : 0,
            "__eline":     settings.espLine     ? 1   : 0,
            "__edist":     settings.espDistance ? 120 : 0,
            "__edistance": settings.espDistance ? 1   : 0,
            "__efull":     settings.espSkeleton ? 1   : 0,

            // Enemy counter
            "__hot": settings.enemyCounter ? 31 : 0,

            // Camera fixed values
            "__cgwas": 1, "__cgw": 10, "__cgc": 1,
            "__mcwas": 1, "__edir": 1, "__moco": 1, "__xrwas": 1,
            "__elag": 0, "__cage": 0, "__cghp": 0,

            // ── Q-SERIES ──────────────────────────────────────────────────────
            // __q17 = FOV circle radius = aimbot lock radius (SAME VALUE)
            // When Lo adjusts the slider, this updates → aimbot lock radius changes
            "__q00": 31, "__q01": 1, "__q02": 1, "__q03": 1,
            "__q04": 1,  "__q05": 1, "__q06": 1, "__q07": 31,

            // __q08 = aim range (same as FOV when aimbot on)
            "__q08": aimbotOn ? fovRadius : 0,

            "__q09": 0, "__q10": 1, "__q11": 1, "__q14": 5,

            // __q15 = aimbot strength
            "__q15": aimbotOn ? aimStrength : 0,

            // __q16 = base radius (fixed 75 from working plist)
            "__q16": 75,

            // __q17 = FOV lock radius ← THIS IS THE KEY ONE
            // Circle on screen = this value = aimbot only targets inside this radius
            "__q17": (settings.fovCircle || aimbotOn) ? fovRadius : 0,

            // __q18 = lock speed / aim pull strength
            "__q18": aimbotOn ? aimStrength : 1,

            // __q19 = fire rate (bullet speed)
            "__q19": settings.bulletSpeed ? 10 : 1,

            // __q20 = speed multiplier (5x = value 5)
            "__q20": settings.speedHack ? 5 : 1,

            // __q21 = enemy counter range (metres)
            "__q21": settings.enemyCounter ? settings.enemyDistance : 0,

            // Anti-leak
            "bind": hwidHash(),
            "ts":   ts,
            "ttl":  ttl,
            "v":    2,
        ]

        return try? JSONSerialization.data(
            withJSONObject: payload,
            options: [.prettyPrinted, .sortedKeys]
        )
    }
}
