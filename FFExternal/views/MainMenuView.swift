import SwiftUI

struct MainMenuView: View {
    let licenseInfo: LicenseInfo
    let onLogout:    () -> Void

    @Environment(\.ffLanguage) private var lang
    @StateObject private var settings = CheatSettings()

    @State private var selectedGame:   FFGame       = .freefireMax
    @State private var injectState:    InjectState  = .idle
    @State private var showLogoutAlert               = false
    @State private var overlayActive                 = false
    @State private var aimbotExpanded                = false
    @State private var counterExpanded               = false
    @State private var revalidateTask: Task<Void, Never>? = nil
    @State private var autoApplyTask:  Task<Void, Never>? = nil

    // MARK: - Inject state
    // .idle    = first run, files not yet written
    // .injected = files already in game container
    // .loading  = writing files
    // .error    = something went wrong

    private enum InjectState: Equatable {
        case idle, loading(String), injected, error(String)
        var isLoading: Bool { if case .loading = self { return true }; return false }
        var hasFiles:  Bool { if case .injected = self { return true }; return false }
    }

    var body: some View {
        ZStack(alignment: .top) {
            FFBackground()

            VStack(spacing: 0) {
                navBar
                licenseCard.padding(.horizontal, 16).padding(.top, 12)
                gamePicker.padding(.horizontal, 16).padding(.top, 14)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        fovAimbotSection
                        counterSection
                        featureSection(header: lang.t("section_esp"))           { espSection }
                        featureSection(header: lang.t("section_movement") + " / " + lang.t("section_combat")) { movementCombatSection }
                        featureSection(header: lang.t("section_stealth"))       { stealthSection }
                        telegramButton
                        Spacer().frame(height: 8)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 110)
                }
            }

            // Inject bar — only shown on first run (.idle) or error
            if !injectState.hasFiles || injectState.isLoading {
                VStack {
                    Spacer()
                    injectBar.padding(.horizontal, 16).padding(.bottom, 32)
                }
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.80), value: injectState)
        .animation(.spring(response: 0.30, dampingFraction: 0.80), value: overlayActive)
        .alert(lang.t("logout_confirm_title"), isPresented: $showLogoutAlert) {
            Button(lang.t("logout_confirm_yes"), role: .destructive) {
                FOVOverlayManager.shared.stop()
                LicenseService.logout()
                onLogout()
            }
            Button(lang.t("logout_confirm_cancel"), role: .cancel) {}
        } message: { Text(lang.t("logout_confirm_msg")) }
        .task { startRevalidation() }
        .onDisappear { revalidateTask?.cancel(); autoApplyTask?.cancel() }
    }

    // MARK: - Auto-apply on any toggle/slider change
    //
    // Bila Lo toggling feature, app silently rewrite config.bin + localConfig.json
    // dalam FF container. Takde button kena tekan — toggle = terus apply.
    // First-time setup still needs the Inject button (download Assembly patch + plist).

    private func autoApply() {
        guard injectState.hasFiles else { return }   // files not injected yet, skip
        autoApplyTask?.cancel()
        autoApplyTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)   // 0.4s debounce
            guard !Task.isCancelled else { return }
            guard let containerPath = ContainerStore.resolveAppContainerPath(bundleID: selectedGame.bundleID) else { return }
            let handle = ContainerStore.grantContainerAccess(containerPath)
            defer { if handle >= 0 { bad_query_release(handle) } }
            let docs = URL(fileURLWithPath: containerPath).appendingPathComponent("Documents")

            // Rewrite config.bin
            let cfgData = SecurityBind.generateConfigBin(settings: settings)
            let cfgURL  = docs.appendingPathComponent("config.bin")
            let cfgTmp  = docs.appendingPathComponent(".\(UUID().uuidString)")
            FileManager.default.createFile(atPath: cfgTmp.path, contents: cfgData)
            rename(cfgTmp.path, cfgURL.path)

            // Rewrite localConfig.json
            guard let lcData = SecurityBind.generateLocalConfig(settings: settings) else { return }
            let lcURL  = docs.appendingPathComponent("localConfig.json")
            let lcTmp  = docs.appendingPathComponent(".\(UUID().uuidString)")
            FileManager.default.createFile(atPath: lcTmp.path, contents: lcData)
            rename(lcTmp.path, lcURL.path)

            log("autoApply: config updated silently")
        }
    }

    // MARK: - Nav bar

    private var navBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(S.appName)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(FFTheme.text)
                Text(selectedGame.displayName)
                    .font(.system(size: 11.5))
                    .foregroundStyle(FFTheme.textSecondary)
            }
            Spacer()
            Button { showLogoutAlert = true } label: {
                HStack(spacing: 5) {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 13, weight: .medium))
                    Text(lang.t("logout"))
                        .font(.system(size: 12.5, weight: .medium, design: .rounded))
                }
                .foregroundStyle(FFTheme.textSecondary)
                .padding(.horizontal, 11).padding(.vertical, 7)
                .background(glassBackground(radius: 10))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 4)
    }

    // MARK: - License card

    private var licenseCard: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(LicenseService.maskedKey(licenseInfo.key))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(FFTheme.accent)
                HStack(spacing: 8) {
                    Label(licenseInfo.iPhoneModel, systemImage: "iphone")
                    Label(licenseInfo.iOSVersion,  systemImage: "applelogo")
                }
                .font(.system(size: 10.5))
                .foregroundStyle(FFTheme.textSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(lang.t("card_expires"))
                    .font(.system(size: 9.5))
                    .foregroundStyle(FFTheme.textTertiary)
                if let exp = licenseInfo.expiryDate {
                    Text(LicenseService.countdownString(from: exp))
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(expiryColor(licenseInfo.expiryDate))
                        .monospacedDigit()
                } else {
                    Text(licenseInfo.expiresAt)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(FFTheme.textSecondary)
                }
            }
        }
        .padding(.horizontal, 15).padding(.vertical, 11)
        .background(glassBackground(radius: 14))
    }

    private func expiryColor(_ date: Date?) -> Color {
        guard let date else { return FFTheme.textSecondary }
        let r = date.timeIntervalSinceNow
        if r < 86400  { return .red.opacity(0.85) }
        if r < 259200 { return .orange.opacity(0.85) }
        return FFTheme.accent
    }

    // MARK: - Game picker

    private var gamePicker: some View {
        HStack(spacing: 0) {
            ForEach(FFGame.allCases, id: \.rawValue) { game in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
                        selectedGame = game
                        if injectState.hasFiles { injectState = .idle }
                    }
                } label: {
                    Text(game.displayName)
                        .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(selectedGame == game ? .white : FFTheme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background {
                            if selectedGame == game {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(FFTheme.accent)
                                    .shadow(color: FFTheme.accent.opacity(0.35), radius: 6, y: 3)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4).background(glassBackground(radius: 14))
    }

    // MARK: - Section wrapper

    private func featureSection<C: View>(header: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            FFSectionHeader(title: header)
            VStack(spacing: 0) { content() }.background(glassBackground(radius: 16))
        }
    }

    // MARK: - FOV + Aimbot

    private var fovAimbotSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            FFSectionHeader(title: lang.t("section_aiming"))
            VStack(spacing: 0) {

                // FOV Circle toggle
                FFToggleRow(
                    icon:     "circle",
                    title:    lang.t("feat_fov"),
                    subtitle: lang.t("feat_fov_sub"),
                    isOn:     $settings.fovCircle
                )
                .onChange(of: settings.fovCircle) { active in
                    syncOverlay(active)
                    autoApply()
                }

                // Radius slider — always visible
                FFDivider()
                FFSlider(label: lang.t("slider_fov_radius"), value: $settings.fovRadius, range: 0...200)
                    .onChange(of: settings.fovRadius) { newR in
                        if overlayActive {
                            FOVOverlayManager.shared.setRadius(newR, settings: settings, game: selectedGame)
                        }
                        autoApply()
                    }

                // Overlay active badge
                if overlayActive {
                    HStack(spacing: 5) {
                        Circle().fill(Color.green).frame(width: 6, height: 6)
                        Text("Overlay active — shake to toggle")
                            .font(.system(size: 10.5))
                            .foregroundStyle(FFTheme.textSecondary)
                        Spacer()
                        Text("radius \(settings.fovRadius)px")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(FFTheme.accent.opacity(0.75))
                    }
                    .padding(.horizontal, 15).padding(.bottom, 8)
                    .transition(.opacity)
                }

                FFDivider()

                // AimSilent
                FFToggleRow(
                    icon:     "wind",
                    title:    lang.t("feat_aimsilent"),
                    subtitle: lang.t("feat_aimsilent_sub"),
                    isOn:     $settings.aimSilent
                )
                .onChange(of: settings.aimSilent) { active in
                    syncOverlay(active); autoApply()
                }

                FFDivider()

                // Aimbot (expandable)
                VStack(spacing: 0) {
                    HStack(spacing: 13) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(settings.aimbot ? FFTheme.accent.opacity(0.18) : Color.white.opacity(0.07))
                                .frame(width: 34, height: 34)
                            Image(systemName: "scope")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(settings.aimbot ? FFTheme.accent : FFTheme.textSecondary)
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(lang.t("feat_aimbot"))
                                .font(.system(size: 14.5, weight: .medium, design: .rounded))
                                .foregroundStyle(FFTheme.text)
                            Text(lang.t("feat_aimbot_sub"))
                                .font(.system(size: 11.5))
                                .foregroundStyle(FFTheme.textSecondary)
                        }
                        Spacer()
                        Button {
                            withAnimation(.spring(response: 0.30, dampingFraction: 0.78)) { aimbotExpanded.toggle() }
                        } label: {
                            Image(systemName: aimbotExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(FFTheme.textSecondary)
                                .frame(width: 26, height: 26)
                        }
                        .buttonStyle(.plain)
                        FFTogglePill(isOn: $settings.aimbot)
                            .onChange(of: settings.aimbot) { active in
                                syncOverlay(active); autoApply()
                            }
                    }
                    .padding(.horizontal, 15).padding(.vertical, 10)

                    if aimbotExpanded {
                        FFDivider()
                        HStack(spacing: 0) {
                            ForEach(AimbotTarget.allCases, id: \.rawValue) { t in
                                Button {
                                    settings.aimbotTarget = t; autoApply()
                                } label: {
                                    VStack(spacing: 3) {
                                        Image(systemName: t.icon)
                                            .font(.system(size: 12, weight: .medium))
                                        Text(lang.t("target_\(["head","neck","body"][t.rawValue])"))
                                            .font(.system(size: 10.5, weight: .medium, design: .rounded))
                                    }
                                    .foregroundStyle(settings.aimbotTarget == t ? FFTheme.accent : FFTheme.textSecondary)
                                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                                    .background(settings.aimbotTarget == t ? FFTheme.accentSoft : Color.clear)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                }
                                .buttonStyle(.plain)
                                .animation(.spring(response: 0.25, dampingFraction: 0.75), value: settings.aimbotTarget)
                            }
                        }
                        .padding(.horizontal, 15).padding(.vertical, 8)

                        FFDivider()
                        FFSlider(label: lang.t("slider_strength"), value: $settings.aimbotStrength, range: 0...100, unit: "%")
                            .onChange(of: settings.aimbotStrength) { _ in autoApply() }

                        HStack(spacing: 5) {
                            Image(systemName: "link.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(FFTheme.accent.opacity(0.70))
                            Text("Lock radius = FOV size (\(settings.fovRadius)px)")
                                .font(.system(size: 10.5))
                                .foregroundStyle(FFTheme.textTertiary)
                        }
                        .padding(.horizontal, 15).padding(.bottom, 10)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .animation(.spring(response: 0.30, dampingFraction: 0.78), value: aimbotExpanded)

            }
            .background(glassBackground(radius: 16))
        }
    }

    // MARK: - Enemy counter

    private var counterSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            FFSectionHeader(title: lang.t("section_hud"))
            VStack(spacing: 0) {
                FFToggleRow(icon: "person.3.sequence.fill", title: lang.t("feat_counter"), subtitle: lang.t("feat_counter_sub"), isOn: $settings.enemyCounter)
                    .onChange(of: settings.enemyCounter) { _ in autoApply() }
                if settings.enemyCounter {
                    FFDivider()
                    FFSlider(label: lang.t("slider_distance"), value: $settings.enemyDistance, range: 0...300, unit: lang.t("lbl_metres"))
                        .onChange(of: settings.enemyDistance) { _ in autoApply() }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .background(glassBackground(radius: 16))
            .animation(.spring(response: 0.30, dampingFraction: 0.80), value: settings.enemyCounter)
        }
    }

    // MARK: - ESP

    @ViewBuilder
    private var espSection: some View {
        FFToggleRow(icon: "square.dashed",  title: lang.t("feat_esp_box"),      subtitle: lang.t("feat_esp_box_sub"),      isOn: $settings.espBox)
            .onChange(of: settings.espBox)      { _ in autoApply() }
        FFDivider()
        FFToggleRow(icon: "line.diagonal",  title: lang.t("feat_esp_line"),     subtitle: lang.t("feat_esp_line_sub"),     isOn: $settings.espLine)
            .onChange(of: settings.espLine)     { _ in autoApply() }
        FFDivider()
        FFToggleRow(icon: "heart.fill",     title: lang.t("feat_esp_health"),   subtitle: lang.t("feat_esp_health_sub"),   isOn: $settings.espHealth)
            .onChange(of: settings.espHealth)   { _ in autoApply() }
        FFDivider()
        FFToggleRow(icon: "tag.fill",       title: lang.t("feat_esp_name"),     subtitle: lang.t("feat_esp_name_sub"),     isOn: $settings.espName)
            .onChange(of: settings.espName)     { _ in autoApply() }
        FFDivider()
        FFToggleRow(icon: "ruler",          title: lang.t("feat_esp_distance"), subtitle: lang.t("feat_esp_distance_sub"), isOn: $settings.espDistance)
            .onChange(of: settings.espDistance) { _ in autoApply() }
        FFDivider()
        FFToggleRow(icon: "figure.stand",   title: lang.t("feat_esp_skeleton"), subtitle: lang.t("feat_esp_skeleton_sub"), isOn: $settings.espSkeleton)
            .onChange(of: settings.espSkeleton) { _ in autoApply() }
    }

    // MARK: - Movement + Combat

    @ViewBuilder
    private var movementCombatSection: some View {
        FFToggleRow(icon: "figure.run",                       title: lang.t("feat_speed"),       subtitle: lang.t("feat_speed_sub"),       isOn: $settings.speedHack)
            .onChange(of: settings.speedHack)   { _ in autoApply() }
        FFDivider()
        FFToggleRow(icon: "bolt.fill",                        title: lang.t("feat_bulletspeed"), subtitle: lang.t("feat_bulletspeed_sub"), isOn: $settings.bulletSpeed)
            .onChange(of: settings.bulletSpeed) { _ in autoApply() }
        FFDivider()
        FFToggleRow(icon: "gauge.with.dots.needle.67percent", title: lang.t("feat_fps"),         subtitle: lang.t("feat_fps_sub"),         isOn: $settings.fps144)
            .onChange(of: settings.fps144)      { _ in autoApply() }
    }

    // MARK: - Stealth

    @ViewBuilder
    private var stealthSection: some View {
        FFToggleRow(icon: "eye.slash.fill", title: lang.t("feat_streamproof"), subtitle: lang.t("feat_streamproof_sub"), isOn: $settings.streamproof)
            .onChange(of: settings.streamproof) { _ in autoApply() }
    }

    // MARK: - Telegram

    private var telegramButton: some View {
        Button {
            if let url = URL(string: S.telegramURL) {
                UIApplication.shared.open(url)
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(FFTheme.textSecondary)
                Text(S.telegramCTA)
                    .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(FFTheme.text)
                Spacer()
                Text(S.telegramHandle)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(FFTheme.accent.opacity(0.75))
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(FFTheme.textTertiary)
            }
            .padding(.horizontal, 15).padding(.vertical, 13)
            .background(glassBackground(radius: 14))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Inject bar (first-time only)

    private var injectBar: some View {
        VStack(spacing: 0) {
            if case .loading(let msg) = injectState {
                Text(msg).font(.system(size: 11.5)).foregroundStyle(FFTheme.textSecondary)
                    .padding(.bottom, 8).transition(.opacity)
            }
            if case .error(let msg) = injectState {
                Text(msg).font(.system(size: 11.5)).foregroundStyle(Color(red: 1, green: 0.38, blue: 0.38))
                    .padding(.bottom, 8).transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            HStack(spacing: 10) {
                FFPrimaryButton(
                    title:   injectState.isLoading ? lang.t("injecting") : lang.t("inject"),
                    icon:    "arrow.down.to.line.circle.fill",
                    loading: injectState.isLoading,
                    tint:    FFTheme.accent
                ) { performInject() }

                Button { performRestore() } label: {
                    Image(systemName: "arrow.uturn.backward.circle.fill")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(FFTheme.textSecondary)
                        .frame(width: 48, height: 48)
                        .background(glassBackground(radius: 14))
                }
                .buttonStyle(.plain).frame(width: 48)
            }
        }
        .padding(14)
        .background(glassBackground(radius: 20))
    }

    // MARK: - Overlay sync

    private func syncOverlay(_ active: Bool) {
        let anyAim = settings.aimbot || settings.aimSilent || settings.fovCircle
        if anyAim && !overlayActive {
            FOVOverlayManager.shared.start(radius: settings.fovRadius, settings: settings)
            overlayActive = true
        } else if !anyAim && overlayActive {
            FOVOverlayManager.shared.stop()
            overlayActive = false
        }
    }

    // MARK: - First-time inject

    private func performInject() {
        guard case .idle = injectState else { return }
        withAnimation { injectState = .loading(lang.t("loading_files")) }
        Task {
            do {
                try await FFCheatService.inject(game: selectedGame, settings: settings)
                await MainActor.run {
                    withAnimation { injectState = .injected }
                    if settings.aimbot || settings.aimSilent || settings.fovCircle {
                        FOVOverlayManager.shared.start(radius: settings.fovRadius, settings: settings)
                        overlayActive = true
                    }
                }
            } catch {
                await MainActor.run {
                    withAnimation { injectState = .error(error.localizedDescription) }
                    Task {
                        try? await Task.sleep(nanoseconds: 3_500_000_000)
                        withAnimation { injectState = .idle }
                    }
                }
            }
        }
    }

    private func performRestore() {
        Task {
            do {
                try FFCheatService.restore(game: selectedGame)
                FOVOverlayManager.shared.stop()
                await MainActor.run {
                    withAnimation { injectState = .idle; overlayActive = false }
                }
            } catch {
                await MainActor.run {
                    withAnimation { injectState = .error(error.localizedDescription) }
                    Task {
                        try? await Task.sleep(nanoseconds: 2_500_000_000)
                        withAnimation { injectState = .idle }
                    }
                }
            }
        }
    }

    // MARK: - Background revalidation

    private func startRevalidation() {
        revalidateTask?.cancel()
        revalidateTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                guard !Task.isCancelled else { break }
                let ok = await LicenseService.revalidateBackground(key: licenseInfo.key)
                if !ok { await MainActor.run { LicenseService.logout(); onLogout() } }
            }
        }
    }
}
