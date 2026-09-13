import SwiftUI

struct LoginView: View {
    @Environment(\.ffLanguage) private var lang
    var onLogin: (LicenseInfo) -> Void

    @State private var key:        String        = ""
    @State private var state:      LoginState    = .idle
    @State private var errorMsg:   String        = ""
    @FocusState private var keyFieldFocused: Bool

    private enum LoginState { case idle, loading, error }

    // Fast-restore stored key on appear
    @State private var didRestoreAttempt = false

    var body: some View {
        ZStack {
            FFBackground()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    Spacer().frame(height: 72)

                    // ── Logo mark (geometry only — no crosshair, no weapon) ──
                    LogoMark()
                        .padding(.bottom, 28)

                    // ── Title ─────────────────────────────────────────────────
                    VStack(spacing: 6) {
                        Text(S.appName)
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(FFTheme.text)
                        Text(lang.t("login_subtitle"))
                            .font(.system(size: 13))
                            .foregroundStyle(FFTheme.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.bottom, 36)

                    // ── Key card ──────────────────────────────────────────────
                    VStack(spacing: 0) {
                        // Key field
                        HStack(spacing: 10) {
                            Image(systemName: "key.fill")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(FFTheme.textSecondary)

                            TextField(lang.t("key_placeholder"), text: $key)
                                .font(.system(size: 14, design: .monospaced))
                                .foregroundStyle(FFTheme.text)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.characters)
                                .submitLabel(.go)
                                .focused($keyFieldFocused)
                                .onSubmit { validate() }
                                .tint(FFTheme.accent)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 15)

                        FFDivider()

                        // Validate button
                        FFPrimaryButton(
                            title: state == .loading ? lang.t("validating") : lang.t("validate"),
                            icon:  state == .loading ? nil : "lock.open.fill",
                            loading: state == .loading
                        ) {
                            validate()
                        }
                        .padding(14)
                    }
                    .background(glassBackground(radius: 18))
                    .padding(.horizontal, 24)

                    // ── Error message ─────────────────────────────────────────
                    if state == .error {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 12))
                            Text(errorMsg)
                                .font(.system(size: 12.5))
                        }
                        .foregroundStyle(Color(red: 1.0, green: 0.38, blue: 0.38))
                        .padding(.top, 14)
                        .padding(.horizontal, 28)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    Spacer().frame(height: 60)
                }
            }
        }
        .task { await attemptFastRestore() }
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: state)
    }

    // MARK: - Actions

    private func validate() {
        guard !key.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        keyFieldFocused = false
        state = .loading
        errorMsg = ""

        Task {
            do {
                let info = try await LicenseService.validate(key: key.trimmingCharacters(in: .whitespaces))
                await MainActor.run {
                    state = .idle
                    onLogin(info)
                }
            } catch let err as LicenseError {
                await MainActor.run {
                    state    = .error
                    errorMsg = localizedError(err)
                }
            } catch {
                await MainActor.run {
                    state    = .error
                    errorMsg = lang.t("key_invalid")
                }
            }
        }
    }

    private func attemptFastRestore() async {
        guard !didRestoreAttempt else { return }
        didRestoreAttempt = true
        if let info = await LicenseService.restoreSession() {
            await MainActor.run { onLogin(info) }
        }
    }

    private func localizedError(_ err: LicenseError) -> String {
        switch err {
        case .deviceMismatch: return lang.t("err_device_mismatch")
        case .expired:        return lang.t("err_expired")
        default:              return lang.t("key_invalid")
        }
    }
}

// MARK: - Logo Mark (abstract geometric, no weapon/crosshair)

private struct LogoMark: View {
    @State private var pulse = false

    var body: some View {
        ZStack {
            // Outer glow ring
            Circle()
                .strokeBorder(FFTheme.accent.opacity(pulse ? 0.06 : 0.14), lineWidth: 1)
                .frame(width: 90, height: 90)
                .scaleEffect(pulse ? 1.12 : 1.0)
                .animation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true), value: pulse)

            // Middle ring
            Circle()
                .strokeBorder(FFTheme.accent.opacity(0.22), lineWidth: 1.5)
                .frame(width: 68, height: 68)

            // Core hexagon-ish shape
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(FFTheme.accentSoft)
                    .frame(width: 52, height: 52)

                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [FFTheme.glassBorderHi, FFTheme.glassBorder],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
                    .frame(width: 52, height: 52)

                // Abstract: three stacked horizontal lines (signal / data motif)
                VStack(spacing: 5) {
                    ForEach([1.0, 0.65, 0.35], id: \.self) { opacity in
                        Capsule()
                            .fill(FFTheme.accent.opacity(opacity))
                            .frame(width: 24 * opacity + 4, height: 2.5)
                    }
                }
            }
        }
        .onAppear { pulse = true }
    }
}
