import Foundation
import SwiftUI

// MARK: - Aimbot Target

enum AimbotTarget: Int, CaseIterable {
    case head = 0
    case neck = 1
    case body = 2

    var displayName: String {
        switch self {
        case .head: return "Head"
        case .neck: return "Neck"
        case .body: return "Body"
        }
    }

    var icon: String {
        switch self {
        case .head: return "scope"
        case .neck: return "person.bust"
        case .body: return "figure.stand"
        }
    }
}

// MARK: - CheatSettings

final class CheatSettings: ObservableObject {

    // Aiming
    @AppStorage("ff_aimSilent")        var aimSilent:       Bool = false
    @AppStorage("ff_aimbot")           var aimbot:          Bool = false
    @AppStorage("ff_aimbotTargetRaw")  var aimbotTargetRaw: Int  = 0
    @AppStorage("ff_aimbotStrength")   var aimbotStrength:  Int  = 60
    @AppStorage("ff_fovCircle")        var fovCircle:       Bool = false
    @AppStorage("ff_fovRadius")        var fovRadius:       Int  = 100

    // Movement
    @AppStorage("ff_speedHack")        var speedHack:       Bool = false

    // Combat
    @AppStorage("ff_bulletSpeed")      var bulletSpeed:     Bool = false
    @AppStorage("ff_fps144")           var fps144:          Bool = false

    // ESP
    @AppStorage("ff_espBox")           var espBox:          Bool = false
    @AppStorage("ff_espLine")          var espLine:         Bool = false
    @AppStorage("ff_espHealth")        var espHealth:       Bool = false
    @AppStorage("ff_espName")          var espName:         Bool = false
    @AppStorage("ff_espDistance")      var espDistance:     Bool = false
    @AppStorage("ff_espSkeleton")      var espSkeleton:     Bool = false

    // HUD
    @AppStorage("ff_enemyCounter")     var enemyCounter:    Bool = false
    @AppStorage("ff_enemyDistance")    var enemyDistance:   Int  = 150

    // Stealth
    @AppStorage("ff_streamproof")      var streamproof:     Bool = false

    var aimbotTarget: AimbotTarget {
        get { AimbotTarget(rawValue: aimbotTargetRaw) ?? .head }
        set { aimbotTargetRaw = newValue.rawValue }
    }

    var anyESP: Bool {
        espBox || espLine || espHealth || espName || espDistance || espSkeleton
    }
}
