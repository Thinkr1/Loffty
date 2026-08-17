//
//  OnboardingView.swift
//  Loffty
//
//  Created by Pierre-Louis ML on 11/08/2026.
//

import AppKit
import SwiftUI

@MainActor
final class OnboardingOpener: NSObject, NSWindowDelegate {
    static let shared = OnboardingOpener()
    static let contentSize = NSSize(width: 400, height: 620)
    static let cornerRadius: CGFloat = 34

    private var window: NSWindow?
    private var onComplete: (() -> Void)?
    private var didFinish = false

    func present(onComplete: @escaping () -> Void) {
        self.onComplete = onComplete
        didFinish = false
        ensureWindow()
        guard let window else { return }
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    func finish() {
        guard !didFinish else { return }
        didFinish = true
        OnboardingFlow.markCompleted()
        window?.delegate = nil
        window?.orderOut(nil)
        window = nil
        let done = onComplete
        onComplete = nil
        done?()
    }

    func windowWillClose(_ notification: Notification) {
        finish()
    }

    private func ensureWindow() {
        guard window == nil else { return }

        let w = OnboardingPanel(
            contentRect: NSRect(origin: .zero, size: Self.contentSize),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        w.isFloatingPanel = true
        w.level = .floating
        w.title = "Welcome to Loffty"
        w.isMovableByWindowBackground = true
        w.backgroundColor = .clear
        w.isOpaque = false
        w.hasShadow = true
        w.hidesOnDeactivate = false
        w.isReleasedWhenClosed = false
        w.animationBehavior = .documentWindow
        w.isRestorable = false
        w.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        w.delegate = self

        let hosting = NSHostingView(
            rootView: OnboardingView(onFinished: { [weak self] in
                self?.finish()
            })
        )
        hosting.frame = NSRect(origin: .zero, size: Self.contentSize)
        w.contentView = Self.makeGlassChrome(hosting: hosting)
        window = w
    }

    private static func makeGlassChrome(hosting: NSView) -> NSView {
        #if compiler(>=6.2)
            if #available(macOS 26.0, *) {
                let glass = NSGlassEffectView()
                glass.cornerRadius = cornerRadius
                glass.style = .regular
                glass.clipsToBounds = true
                glass.contentView = hosting
                hosting.autoresizingMask = [.width, .height]
                hosting.frame = glass.bounds
                return glass
            }
        #endif
        return NSVisualEffectView.onboardingChrome(
            subview: hosting,
            cornerRadius: cornerRadius
        )
    }
}

private final class OnboardingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

extension NSVisualEffectView {
    fileprivate static func onboardingChrome(
        subview: NSView,
        cornerRadius: CGFloat
    ) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.state = .active
        view.material = .hudWindow
        view.maskImage = .onboardingRoundedMask(cornerRadius: cornerRadius)
        view.wantsLayer = true
        view.layer?.cornerRadius = cornerRadius
        view.layer?.masksToBounds = true
        subview.frame = view.bounds
        subview.autoresizingMask = [.width, .height]
        view.addSubview(subview)
        return view
    }
}

extension NSImage {
    fileprivate static func onboardingRoundedMask(cornerRadius: CGFloat)
        -> NSImage
    {
        let size = NSSize(width: cornerRadius * 2, height: cornerRadius * 2)
        return NSImage(size: size, flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(
                roundedRect: rect,
                xRadius: cornerRadius,
                yRadius: cornerRadius
            ).fill()
            return true
        }
    }
}

enum OnboardingFlow {
    enum Step: Int, CaseIterable, Identifiable {
        case welcome
        case setup
        case alerts
        case ready

        var id: Int { rawValue }
    }

    nonisolated static func shouldPresentOnboarding(
        hasCompletedOnboarding: Bool
    ) -> Bool {
        !hasCompletedOnboarding
    }

    nonisolated static func transitionGroup(for step: Step) -> String {
        switch step {
        case .welcome: "welcome"
        case .setup: "setup"
        case .alerts: "alerts"
        case .ready: "ready"
        }
    }

    nonisolated static func primaryTitle(for step: Step) -> String {
        switch step {
        case .welcome: "Get Started"
        case .setup: "Continue"
        case .alerts: "Continue"
        case .ready: "Start Loffty"
        }
    }

    nonisolated static func next(
        _ step: Step,
        notificationsEnabled: Bool = true
    ) -> Step? {
        guard let candidate = Step(rawValue: step.rawValue + 1) else {
            return nil
        }
        if candidate == .alerts, !notificationsEnabled {
            return Step(rawValue: candidate.rawValue + 1)
        }
        return candidate
    }

    nonisolated static func previous(
        _ step: Step,
        notificationsEnabled: Bool = true
    ) -> Step? {
        guard let candidate = Step(rawValue: step.rawValue - 1) else {
            return nil
        }
        if candidate == .alerts, !notificationsEnabled {
            return Step(rawValue: candidate.rawValue - 1)
        }
        return candidate
    }

    nonisolated static func finishesOnPrimaryAction(_ step: Step) -> Bool {
        step == .ready
    }

    nonisolated static func showMenuBarIcon(hidingMenuBarItem: Bool) -> Bool {
        !hidingMenuBarItem
    }

    nonisolated static func hideMenuBarItem(showingMenuBarIcon: Bool) -> Bool {
        !showingMenuBarIcon
    }

    @MainActor
    static func markCompleted(settings: AppSettings = .shared) {
        settings.hasCompletedOnboarding = true
    }
}

struct OnboardingView: View {
    let onFinished: () -> Void

    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.colorScheme) private var scheme
    @Namespace private var glassNamespace

    @State private var step: OnboardingFlow.Step = .welcome
    @State private var accessibilityTrusted = PrivacyAccess
        .isAccessibilityTrusted
    @State private var appeared = false
    @State private var notificationPrefsStamp = 0

    private let version = AppUpdater.shared.currentVersion
    private let morph = Animation.spring(response: 0.58, dampingFraction: 0.86)

    private var showMenuBarIcon: Binding<Bool> {
        Binding(
            get: {
                OnboardingFlow.showMenuBarIcon(
                    hidingMenuBarItem: settings.hideMenuBarItem
                )
            },
            set: {
                settings.hideMenuBarItem = OnboardingFlow.hideMenuBarItem(
                    showingMenuBarIcon: $0
                )
            }
        )
    }

    var body: some View {
        OnboardingGlassStack(spacing: 28) {
            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 20)
                    .padding(.top, 20)

                ZStack {
                    stepBody
                        .id(OnboardingFlow.transitionGroup(for: step))
                        .transition(contentTransition)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 22)
                .padding(.top, 10)

                footer
                    .padding(.horizontal, 28)
                    .padding(.bottom, 22)
                    .padding(.top, 10)
            }
        }
        .frame(
            width: OnboardingOpener.contentSize.width,
            height: OnboardingOpener.contentSize.height
        )
        .onAppear {
            withAnimation(.easeOut(duration: 0.65)) { appeared = true }
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSApplication.didBecomeActiveNotification
            )
        ) { _ in
            accessibilityTrusted = PrivacyAccess.isAccessibilityTrusted
            settings.refreshLaunchAtLogin()
            NotificationStyleCheck.synchronize()
            notificationPrefsStamp += 1
        }
    }

    private var contentTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity
                .combined(with: .scale(scale: 0.98))
                .combined(with: .offset(y: 12)),
            removal: .opacity
                .combined(with: .scale(scale: 1.015))
                .combined(with: .offset(y: -8))
        )
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            if step == .welcome {
                Button {
                    onFinished()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .onboardingGlass(Circle(), interactive: true, scheme: scheme)
                .help("Close")
            } else {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 32, height: 32)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
            }

            Spacer(minLength: 0)

            if step != .welcome {
                Button("Back") { goBack() }
                    .controlSize(.small)
                    .settingsButton()
            }
        }
        .frame(height: 32)
        .animation(morph, value: step)
    }

    @ViewBuilder
    private var stepBody: some View {
        switch step {
        case .welcome:
            welcomeBody
        case .setup:
            setupBody
        case .alerts:
            alertsBody
        case .ready:
            readyBody
        }
    }

    private var welcomeBody: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 12)

            VStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 72, height: 72)
                    .clipShape(
                        RoundedRectangle(cornerRadius: 17, style: .continuous)
                    )
                    .shadow(color: .black.opacity(0.28), radius: 20, y: 10)
                    .scaleEffect(appeared ? 1 : 0.88)
                    .opacity(appeared ? 1 : 0)

                Text("Welcome to Loffty")
                    .font(.system(size: 24, weight: .bold))
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 6)
            }

            Spacer(minLength: 28)

            heroCard
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 16)
                .scaleEffect(appeared ? 1 : 0.97)

            Spacer(minLength: 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var setupBody: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 8) {
                Text("Quick Setup")
                    .font(.system(size: 22, weight: .bold))
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .padding(.top, 4)

            VStack(spacing: 8) {
                toggleRow("Launch at Login", isOn: $settings.launchAtLogin)
                toggleRow(
                    "Replace System HUDs",
                    isOn: $settings.replaceSystemHUD
                )
                toggleRow("Bluetooth Overlay", isOn: $settings.bluetoothHUD)
                toggleRow("AirDrop in Notch", isOn: $settings.airDropHUD)
                toggleRow(
                    "Notifications in Notch",
                    isOn: $settings.notificationsHUD
                )
                toggleRow("Menu Bar Icon", isOn: showMenuBarIcon)
            }
            .padding(12)
            .onboardingGlass(
                RoundedRectangle(cornerRadius: 22, style: .continuous),
                interactive: false,
                scheme: scheme,
                clear: true
            )
            .onboardingGlassID("mainCard", in: glassNamespace)
            .onboardingGlassTransition(.matchedGeometry)

            permissionsStrip

            if settings.launchAtLoginNeedsApproval {
                HStack(spacing: 8) {
                    Text("Login Items still needs approval.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    Button("Open") { PrivacyAccess.openLoginItemsSettings() }
                        .controlSize(.small)
                        .settingsButton()
                }
            }

            Spacer(minLength: 0)
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .topLeading
        )
    }

    private var alertsBody: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 8) {
                Text("Hide System Banners")
                    .font(.system(size: 22, weight: .bold))
                Image(systemName: "bell.slash.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .padding(.top, 4)

            Text(
                "Turn off Desktop for each app so banners don’t appear on screen. Keep Allow Notifications and Notification Centre on."
            )
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 8) {
                ForEach(NotificationApp.allCases, id: \.self) { app in
                    AlertStyleOnboardingStep(
                        app: app,
                        isComplete: hidesSystemBanner(app),
                        scheme: scheme
                    )
                }
            }
            .padding(12)
            .onboardingGlass(
                RoundedRectangle(cornerRadius: 22, style: .continuous),
                interactive: false,
                scheme: scheme,
                clear: true
            )
            .onboardingGlassID("mainCard", in: glassNamespace)
            .onboardingGlassTransition(.matchedGeometry)

            HStack(spacing: 8) {
                Text(
                    NotificationDatabaseReader.canReadDatabase()
                        ? "Full Disk Access is granted."
                        : "Full Disk Access is needed once banners are hidden."
                )
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                if !NotificationDatabaseReader.canReadDatabase() {
                    Button("Open") {
                        PrivacyAccess.openFullDiskAccessSettings()
                    }
                    .controlSize(.small)
                    .settingsButton()
                }
            }

            Spacer(minLength: 0)
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .topLeading
        )
    }

    private func hidesSystemBanner(_ app: NotificationApp) -> Bool {
        _ = notificationPrefsStamp
        return NotificationStyleCheck.hidesSystemBanner(for: app)
    }

    private var permissionsStrip: some View {
        HStack(spacing: 8) {
            if !accessibilityTrusted {
                Button("Allow Accessibility") {
                    PrivacyAccess.requestAccessibilityPrompt()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        accessibilityTrusted =
                            PrivacyAccess.isAccessibilityTrusted
                    }
                }
                .controlSize(.small)
                .settingsButton()
            } else {
                Label("Accessibility", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)
            }

            Spacer(minLength: 0)

            Button("Bluetooth") {
                PrivacyAccess.requestBluetoothAccess()
            }
            .controlSize(.small)
            .settingsButton()

            Button("Local Network") {
                PrivacyAccess.primeLocalNetworkAccess()
            }
            .controlSize(.small)
            .settingsButton()
        }
    }

    private var readyBody: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 28)
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 68, height: 68)
                .clipShape(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
                .shadow(color: .black.opacity(0.24), radius: 18, y: 8)
            Text("You’re all set!")
                .font(.system(size: 24, weight: .bold))
            Text(
                "Loffty stays in the menu bar. Open settings anytime from the notch or the status item."
            )
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 300)
            Spacer(minLength: 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var heroCard: some View {
        VStack(spacing: 12) {
            Capsule()
                .fill(Color.primary.opacity(0.72))
                .frame(width: 40, height: 3)

            Text("Loffty v\(version)")
                .font(.system(size: 30, weight: .bold))

            Text("Your notch, truly.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 32)
        .padding(.horizontal, 20)
        .onboardingGlass(
            RoundedRectangle(cornerRadius: 22, style: .continuous),
            interactive: false,
            scheme: scheme,
            clear: true
        )
        .onboardingGlassID("mainCard", in: glassNamespace)
        .onboardingGlassTransition(.matchedGeometry)
    }

    private func toggleRow(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 13.5, weight: .medium))
            Spacer(minLength: 8)
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .sensoryFeedback(.selection, trigger: isOn.wrappedValue)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .onboardingGlass(
            RoundedRectangle(cornerRadius: 14, style: .continuous),
            interactive: true,
            scheme: scheme,
            clear: true
        )
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Spacer(minLength: 0)

            Button(action: primaryAction) {
                Text(OnboardingFlow.primaryTitle(for: step))
                    .font(.system(size: 14, weight: .semibold))
                    .frame(minWidth: step == .welcome ? 168 : 128)
            }
            .controlSize(.large)
            .settingsButton(prominent: true)
            .keyboardShortcut(.defaultAction)
            .onboardingGlassID("cta", in: glassNamespace)
            .opacity(appeared || step != .welcome ? 1 : 0)
            .offset(y: appeared || step != .welcome ? 0 : 8)

            Spacer(minLength: 0)
        }
        .animation(morph, value: step)
    }

    private func primaryAction() {
        if OnboardingFlow.finishesOnPrimaryAction(step) {
            onFinished()
        } else {
            goForward()
        }
    }

    private func goForward() {
        guard
            let next = OnboardingFlow.next(
                step,
                notificationsEnabled: settings.notificationsHUD
            )
        else {
            onFinished()
            return
        }
        withAnimation(morph) { step = next }
    }

    private func goBack() {
        guard
            let previous = OnboardingFlow.previous(
                step,
                notificationsEnabled: settings.notificationsHUD
            )
        else { return }
        withAnimation(morph) { step = previous }
    }
}

private struct AlertStyleOnboardingStep: View {
    let app: NotificationApp
    let isComplete: Bool
    var scheme: ColorScheme

    var body: some View {
        HStack(spacing: 10) {
            Image(
                systemName: isComplete
                    ? "checkmark.circle.fill" : "circle"
            )
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(isComplete ? Color.accentColor : .secondary)
            Text("Turn off Desktop for \(app.displayName)")
                .font(.system(size: 13.5, weight: .medium))
            Spacer(minLength: 8)
            if !isComplete {
                Button("Open Settings") {
                    NotificationSettingsLink.openNotificationSettings(
                        for: app
                    )
                }
                .controlSize(.small)
                .settingsButton()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .onboardingGlass(
            RoundedRectangle(cornerRadius: 14, style: .continuous),
            interactive: true,
            scheme: scheme,
            clear: true
        )
    }
}

private struct OnboardingGlassStack<Content: View>: View {
    var spacing: CGFloat = 20
    @ViewBuilder var content: Content

    var body: some View {
        #if compiler(>=6.2)
            if #available(macOS 26.0, *) {
                GlassEffectContainer(spacing: spacing) { content }
            } else {
                content
            }
        #else
            content
        #endif
    }
}

extension View {
    @ViewBuilder
    fileprivate func onboardingGlass<S: InsettableShape>(
        _ shape: S,
        interactive: Bool,
        scheme: ColorScheme,
        clear: Bool = false
    ) -> some View {
        #if compiler(>=6.2)
            if #available(macOS 26.0, *) {
                let base: Glass = clear ? .clear : .regular
                self.glassEffect(
                    interactive ? base.interactive() : base,
                    in: shape
                )
            } else {
                self
                    .background(shape.fill(SettingsChrome.cardFill(scheme)))
                    .overlay(
                        shape.strokeBorder(
                            SettingsChrome.cardStroke(scheme),
                            lineWidth: 1
                        )
                    )
            }
        #else
            self
                .background(shape.fill(SettingsChrome.cardFill(scheme)))
                .overlay(
                    shape.strokeBorder(
                        SettingsChrome.cardStroke(scheme),
                        lineWidth: 1
                    )
                )
        #endif
    }

    @ViewBuilder
    fileprivate func onboardingGlassID(
        _ id: String,
        in namespace: Namespace.ID
    ) -> some View {
        #if compiler(>=6.2)
            if #available(macOS 26.0, *) {
                self.glassEffectID(id, in: namespace)
            } else {
                self
            }
        #else
            self
        #endif
    }

    @ViewBuilder
    fileprivate func onboardingGlassTransition(
        _ kind: OnboardingGlassTransitionKind
    ) -> some View {
        #if compiler(>=6.2)
            if #available(macOS 26.0, *) {
                switch kind {
                case .matchedGeometry:
                    self.glassEffectTransition(.matchedGeometry)
                case .materialize:
                    self.glassEffectTransition(.materialize)
                }
            } else {
                self
            }
        #else
            self
        #endif
    }
}

private enum OnboardingGlassTransitionKind {
    case matchedGeometry
    case materialize
}
