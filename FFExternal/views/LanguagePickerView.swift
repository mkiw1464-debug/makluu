import SwiftUI

struct LanguagePickerView: View {
    @AppStorage(FFLanguage.storageKey) private var storedLang = FFLanguage.english.rawValue
    @Environment(\.ffLanguage) private var lang
    var onContinue: () -> Void

    @State private var selected: FFLanguage = .english

    var body: some View {
        ZStack {
            FFBackground()

            VStack(spacing: 0) {
                // ── Header ────────────────────────────────────────────────────
                VStack(spacing: 8) {
                    Text("FF External")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(FFTheme.text)

                    Text(selected.t("select_language"))
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(FFTheme.textSecondary)
                }
                .padding(.top, 64)
                .padding(.bottom, 32)

                // ── Language list ─────────────────────────────────────────────
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        ForEach(Array(FFLanguage.allCases.enumerated()), id: \.element.id) { idx, language in
                            LanguageRow(language: language, isSelected: selected == language)
                                .onTapGesture {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                        selected = language
                                    }
                                }

                            if idx < FFLanguage.allCases.count - 1 {
                                FFDivider()
                            }
                        }
                    }
                    .background(glassBackground(radius: 18))
                    .padding(.horizontal, 24)
                }

                // ── Continue button ───────────────────────────────────────────
                FFPrimaryButton(title: selected.t("continue"), icon: "arrow.right") {
                    storedLang = selected.rawValue
                    onContinue()
                }
                .padding(.horizontal, 24)
                .padding(.top, 28)
                .padding(.bottom, 40)
            }
        }
        .environment(\.ffLanguage, selected)
        .onAppear {
            selected = FFLanguage(rawValue: storedLang) ?? .english
        }
    }
}

// MARK: - Language Row

private struct LanguageRow: View {
    let language: FFLanguage
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 14) {
            Text(language.flagEmoji)
                .font(.system(size: 24))

            Text(language.displayName)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(isSelected ? FFTheme.accent : FFTheme.text)
                .environment(\.layoutDirection, language.isRTL ? .rightToLeft : .leftToRight)

            Spacer()

            ZStack {
                Circle()
                    .fill(isSelected ? FFTheme.accent : Color.clear)
                    .frame(width: 20, height: 20)
                Circle()
                    .strokeBorder(isSelected ? FFTheme.accent : FFTheme.glassBorder, lineWidth: 1.5)
                    .frame(width: 20, height: 20)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .animation(.spring(response: 0.28, dampingFraction: 0.75), value: isSelected)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(
            isSelected
                ? FFTheme.accentSoft
                : Color.clear
        )
        .animation(.spring(response: 0.28, dampingFraction: 0.75), value: isSelected)
    }
}
