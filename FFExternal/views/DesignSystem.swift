import SwiftUI

// MARK: - Theme

enum FFTheme {
    // Backgrounds
    static let bgBase       = Color(red: 0.040, green: 0.040, blue: 0.110)
    static let bgDeep       = Color(red: 0.025, green: 0.020, blue: 0.080)

    // Accents
    static let accent       = Color(red: 0.380, green: 0.560, blue: 1.000)
    static let accentSoft   = Color(red: 0.380, green: 0.560, blue: 1.000).opacity(0.18)
    static let accentGlow   = Color(red: 0.180, green: 0.380, blue: 0.900).opacity(0.35)

    // Text
    static let text          = Color.white
    static let textSecondary = Color.white.opacity(0.55)
    static let textTertiary  = Color.white.opacity(0.30)

    // Glass surfaces
    static let glass           = Color.white.opacity(0.060)
    static let glassBright     = Color.white.opacity(0.090)
    static let glassBorder     = Color.white.opacity(0.110)
    static let glassBorderHi   = Color.white.opacity(0.240)

    // Toggle
    static let toggleOn        = Color(red: 0.300, green: 0.540, blue: 1.000)
    static let toggleOff       = Color.white.opacity(0.140)

    // Separator
    static let divider         = Color.white.opacity(0.065)

    // Section header
    static let sectionHeader   = Color.white.opacity(0.280)
}

// MARK: - Background

struct FFBackground: View {
    var body: some View {
        ZStack {
            FFTheme.bgBase.ignoresSafeArea()

            // Blue nebula — top-left
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(red: 0.20, green: 0.35, blue: 0.95).opacity(0.18), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 160
                    )
                )
                .frame(width: 320, height: 320)
                .blur(radius: 40)
                .offset(x: -90, y: -160)
                .ignoresSafeArea()

            // Purple nebula — bottom-right
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(red: 0.48, green: 0.10, blue: 0.80).opacity(0.13), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 140
                    )
                )
                .frame(width: 280, height: 280)
                .blur(radius: 50)
                .offset(x: 110, y: 260)
                .ignoresSafeArea()
        }
    }
}

// MARK: - Glass Card

struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat = 16
    var padding: EdgeInsets   = .init(top: 0, leading: 0, bottom: 0, trailing: 0)
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .background(glassBackground(radius: cornerRadius))
    }

    static func bordered(radius: CGFloat = 16) -> some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(FFTheme.glass)
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [FFTheme.glassBorderHi, FFTheme.glassBorder, FFTheme.glassBorder.opacity(0.30)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.75
                    )
            )
    }
}

func glassBackground(radius: CGFloat = 16) -> some View {
    ZStack {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(.ultraThinMaterial)
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(FFTheme.glass)
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    colors: [FFTheme.glassBorderHi, FFTheme.glassBorder, FFTheme.glassBorder.opacity(0.20)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 0.75
            )
    }
    .shadow(color: Color.black.opacity(0.30), radius: 14, x: 0, y: 7)
}

// MARK: - Section Header

struct FFSectionHeader: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
            .foregroundStyle(FFTheme.sectionHeader)
            .kerning(1.4)
            .padding(.horizontal, 2)
    }
}

// MARK: - Glass Toggle Row

struct FFToggleRow: View {
    let icon:     String
    let title:    String
    var subtitle: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 13) {
            // Icon chip
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isOn ? FFTheme.accent.opacity(0.18) : Color.white.opacity(0.07))
                    .frame(width: 34, height: 34)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isOn ? FFTheme.accent : FFTheme.textSecondary)
            }
            .animation(.spring(response: 0.28, dampingFraction: 0.75), value: isOn)

            // Labels
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 14.5, weight: .medium, design: .rounded))
                    .foregroundStyle(FFTheme.text)
                if let sub = subtitle {
                    Text(sub)
                        .font(.system(size: 11.5))
                        .foregroundStyle(FFTheme.textSecondary)
                }
            }

            Spacer(minLength: 0)

            // Custom toggle pill
            FFTogglePill(isOn: $isOn)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) { isOn.toggle() }
        }
    }
}

// MARK: - Toggle Pill

struct FFTogglePill: View {
    @Binding var isOn: Bool

    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule()
                .fill(isOn ? FFTheme.toggleOn : FFTheme.toggleOff)
                .frame(width: 42, height: 24)
                .animation(.spring(response: 0.28, dampingFraction: 0.72), value: isOn)
                .overlay(
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                )

            Circle()
                .fill(.white)
                .frame(width: 18, height: 18)
                .shadow(color: .black.opacity(0.18), radius: 2, x: 0, y: 1)
                .padding(3)
        }
        .frame(width: 42, height: 24)
        .onTapGesture {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) { isOn.toggle() }
        }
    }
}

// MARK: - Glassmorphism Slider

struct FFSlider: View {
    let label:  String
    @Binding var value: Int
    let range:  ClosedRange<Int>
    var unit:   String = ""
    var color:  Color  = FFTheme.accent

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(FFTheme.textSecondary)
                Spacer()
                Text("\(value)\(unit)")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(color)
                    .monospacedDigit()
            }

            Slider(
                value: Binding(
                    get: { Double(value) },
                    set: { value = Int($0.rounded()) }
                ),
                in: Double(range.lowerBound)...Double(range.upperBound),
                step: 1
            )
            .accentColor(color)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 9)
    }
}

// MARK: - Primary Button

struct FFPrimaryButton: View {
    let title:   String
    var icon:    String? = nil
    var loading: Bool    = false
    var tint:    Color   = FFTheme.accent
    let action:  () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if loading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                } else if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(tint)
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.15), Color.clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.75)
            )
            .shadow(color: tint.opacity(0.40), radius: 12, x: 0, y: 6)
        }
        .disabled(loading)
        .buttonStyle(.plain)
    }
}

// MARK: - Divider

struct FFDivider: View {
    var body: some View {
        Rectangle()
            .fill(FFTheme.divider)
            .frame(height: 0.5)
            .padding(.leading, 50)
    }
}
