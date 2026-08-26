//
//  SettingsView.swift
//  Loffty
//
//  Created by Pierre-Louis ML on 10/08/2026.
//

import AppKit
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

enum SettingsPage: String, CaseIterable, Identifiable {
    case general
    case media
    case sensory
    case battery
    case accessories
    case focus
    case airDrop
    case notifications
    case lockScreen
    case weather
    case updates

    enum Region {
        case app
        case overlays
        case footer
    }

    var id: String { rawValue }

    var region: Region {
        switch self {
        case .general, .media: .app
        case .sensory, .battery, .accessories, .focus, .airDrop, .notifications,
            .lockScreen, .weather:
            .overlays
        case .updates: .footer
        }
    }

    var title: String {
        switch self {
        case .general: "General"
        case .media: "Media"
        case .sensory: "Sensory"
        case .battery: "Battery"
        case .accessories: "Accessories"
        case .focus: "Focus"
        case .airDrop: "AirDrop"
        case .notifications: "Notifications"
        case .lockScreen: "Lock Screen"
        case .weather: "Weather"
        case .updates: "Updates"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .media: "play.rectangle.fill"
        case .sensory: "sun.max.fill"
        case .battery: "battery.100percent"
        case .accessories: "airpods.gen3"
        case .focus: "moon.fill"
        case .airDrop: "dot.radiowaves.up.forward"
        case .notifications: "bell.fill"
        case .lockScreen: "lock.fill"
        case .weather: "cloud.sun.fill"
        case .updates: "arrow.down.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .general: .secondary
        case .media: .pink
        case .sensory: .yellow
        case .battery: .green
        case .accessories: .mint
        case .focus: .indigo
        case .airDrop: .blue
        case .notifications: .green
        case .lockScreen: .orange
        case .weather: .cyan
        case .updates: .blue
        }
    }
}

struct SettingsEntry: Identifiable {
    let id: String
    let title: String
    let detail: String?
    let keywords: [String]
    let isEnabled: Bool
    let control: AnyView

    init(
        _ id: String,
        title: String,
        detail: String? = nil,
        keywords: [String] = [],
        isEnabled: Bool = true,
        @ViewBuilder control: () -> some View
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.keywords = keywords
        self.isEnabled = isEnabled
        self.control = AnyView(control())
    }

    func matches(_ tokens: [String]) -> Bool {
        let haystack =
            ([title, detail ?? ""] + keywords)
            .joined(separator: " ")
            .lowercased()
        return tokens.allSatisfy { haystack.contains($0) }
    }
}

struct SettingsGroup: Identifiable {
    let page: SettingsPage
    let title: String
    let note: String?
    let accessory: AnyView?
    let entries: [SettingsEntry]

    var id: String { "\(page.rawValue).\(title)" }

    init(
        page: SettingsPage,
        title: String,
        note: String? = nil,
        accessory: AnyView? = nil,
        entries: [SettingsEntry]
    ) {
        self.page = page
        self.title = title
        self.note = note
        self.accessory = accessory
        self.entries = entries
    }

    func filtered(by tokens: [String]) -> SettingsGroup? {
        guard !tokens.isEmpty else { return self }
        let context = "\(page.title) \(title)".lowercased()
        let matchesContext = tokens.allSatisfy { context.contains($0) }
        let matched =
            matchesContext ? entries : entries.filter { $0.matches(tokens) }
        guard !matched.isEmpty else { return nil }
        return SettingsGroup(
            page: page,
            title: title,
            note: note,
            accessory: accessory,
            entries: matched
        )
    }
}

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var updater = AppUpdater.shared
    // @ObservedObject private var spotifyLibrary = SpotifyLibraryManager.shared

    @AppStorage("settings.selectedPage") private var storedPage =
        SettingsPage.general.rawValue
    @State private var query = ""
    @FocusState private var searchFocused: Bool
    @State private var notificationPrefsStamp = 0

    private var page: SettingsPage {
        SettingsPage(rawValue: storedPage) ?? .general
    }

    private var tokens: [String] {
        query
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
    }

    private var isSearching: Bool { !tokens.isEmpty }

    private var results: [SettingsGroup] {
        let source = isSearching ? groups : groups.filter { $0.page == page }
        return source.compactMap { $0.filtered(by: tokens) }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider().opacity(0.5)
            detail
        }
        .frame(minWidth: 720, minHeight: 580)
        .background(
            VisualEffectBackground(material: .hudWindow)
                .ignoresSafeArea()
        )
        .background {
            Button("Search") { searchFocused = true }
                .keyboardShortcut("f", modifiers: .command)
                .frame(width: 0, height: 0)
                .opacity(0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .onAppear { settings.refreshLaunchAtLogin() }
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSApplication.didBecomeActiveNotification
            )
        ) { _ in
            settings.refreshLaunchAtLogin()
            NotificationStyleCheck.synchronize()
            notificationPrefsStamp += 1
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: 30)

            HStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 34, height: 34)
                Text("Settings")
                    .font(.system(size: 14, weight: .semibold))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 14)

            SearchField(text: $query)
                .focused($searchFocused)
                .padding(.horizontal, 10)
                .padding(.bottom, 8)

            ScrollView {
                GlassStack {
                    VStack(alignment: .leading, spacing: 2) {
                        sidebarSection("General", top: 4)
                        ForEach(pages(in: .app)) { sidebarRow($0) }

                        sidebarSection("Overlays")
                        ForEach(pages(in: .overlays)) { sidebarRow($0) }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
            }
            .scrollIndicators(.never)

            Divider().opacity(0.35).padding(.horizontal, 12)

            VStack(alignment: .leading, spacing: 2) {
                ForEach(pages(in: .footer)) { sidebarRow($0) }
                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: "power")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 18)
                        Text("Quit Loffty")
                            .font(.system(size: 13))
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .frame(height: 32)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut("q", modifiers: .command)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
        }
        .padding(.top, -30)
        .frame(width: 208)
        .background(VisualEffectBackground(material: .hudWindow))
    }

    private func sidebarSection(_ title: String, top: CGFloat = 16) -> some View
    {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 12)
            .padding(.top, top)
            .padding(.bottom, 6)
    }

    private func pages(in region: SettingsPage.Region) -> [SettingsPage] {
        SettingsPage.allCases.filter { $0.region == region }
    }

    private func sidebarRow(_ item: SettingsPage) -> some View {
        SidebarRow(
            page: item,
            isSelected: !isSearching && item == page,
            badge: item == .updates ? updater.currentVersion : nil,
            showsDot: item == .updates && updateAvailable
        ) {
            query = ""
            guard item.rawValue != storedPage else { return }
            withAnimation(.easeInOut(duration: 0.15)) {
                storedPage = item.rawValue
            }
        }
    }

    private var updateAvailable: Bool {
        if case .available = updater.state { return true }
        return false
    }

    private var detail: some View {
        ZStack(alignment: .topLeading) {
            detailPage
                .id(isSearching ? "search" : storedPage)
                .transition(.opacity)
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .topLeading
        )
    }

    private var detailPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: 22)

            Text(isSearching ? "Search" : page.title)
                .font(.system(size: 28, weight: .bold))
                .padding(.horizontal, 26)
                .padding(.bottom, 18)

            if results.isEmpty {
                emptyResults
            } else {
                ScrollView {
                    GlassStack {
                        LazyVStack(alignment: .leading, spacing: 22) {
                            ForEach(results) { group in
                                SettingsCard(
                                    group: group,
                                    showsPage: isSearching,
                                    showsNote: !isSearching
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 26)
                    .padding(.bottom, 28)
                }
                .scrollIndicators(.automatic)
            }
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .topLeading
        )
    }

    private var resultsCaption: String {
        let count = results.reduce(0) { $0 + $1.entries.count }
        let noun = count == 1 ? "match" : "matches"
        return "\(count) \(noun) for “\(query)”"
    }

    private var emptyResults: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.tertiary)
            Text("No settings match “\(query)”")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var groups: [SettingsGroup] {
        generalGroups + mediaGroups + overlayGroups + lockScreenGroups
            + weatherGroups + updateGroups
    }

    private var generalGroups: [SettingsGroup] {
        [
            SettingsGroup(
                page: .general,
                title: "Startup",
                entries: [
                    SettingsEntry(
                        "launchAtLogin",
                        title: "Launch at login",
                        keywords: ["startup", "boot", "open"]
                    ) {
                        SettingsToggle(isOn: $settings.launchAtLogin)
                    }
                ]
                    + (settings.launchAtLoginNeedsApproval
                        ? [
                            SettingsEntry(
                                "launchApproval",
                                title: "Approval required",
                                detail:
                                    "macOS is waiting for you to allow Loffty in Login Items.",
                                keywords: ["login items", "permission"]
                            ) {
                                Button("Open") {
                                    SMAppService.openSystemSettingsLoginItems()
                                }
                                .controlSize(.small)
                                .settingsButton()
                            }
                        ] : [])
            ),
            SettingsGroup(
                page: .general,
                title: "Menu Bar",
                entries: [
                    SettingsEntry(
                        "hideMenuBarItem",
                        title: "Hide menu bar icon",
                        detail: "Reopen settings from the notch.",
                        keywords: ["status item", "icon"]
                    ) {
                        SettingsToggle(isOn: $settings.hideMenuBarItem)
                    }
                ]
            ),
            SettingsGroup(
                page: .general,
                title: "Notch",
                note:
                    "The overlay duration applies to every notch overlay: volume, brightness, battery, Bluetooth and Focus. Swipe sideways with two fingers on the expanded notch to switch between music and weather.",
                entries: [
                    SettingsEntry(
                        "extendNotch",
                        title: "Extend notch around media",
                        keywords: ["grow", "widen", "playing"]
                    ) {
                        SettingsToggle(isOn: $settings.extendNotch)
                    },
                    SettingsEntry(
                        "hudDuration",
                        title: "Overlay duration",
                        keywords: ["hud", "timing", "seconds", "dismiss"],
                        isEnabled: settings.anyHUDEnabled
                    ) {
                        HStack(spacing: 10) {
                            SettingsSlider(
                                value: $settings.hudDuration,
                                range: 1...3,
                                step: 0.25
                            )
                            .frame(width: 120)
                            Text(String(format: "%.2fs", settings.hudDuration))
                                .font(.system(size: 11.5))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(width: 40, alignment: .trailing)
                        }
                    },
                ]
            ),
            SettingsGroup(
                page: .general,
                title: "Full Screen",
                note:
                    "The notch hides while a matching full screen app is in front. Volume, brightness and other overlays still appear.",
                entries: fullScreenHideEntries
            ),
        ]
    }

    private var fullScreenHideEntries: [SettingsEntry] {
        [
            SettingsEntry(
                "hideNotchInFullScreen",
                title: "Hide in any full screen app",
                keywords: [
                    "fullscreen", "full screen", "movie", "video", "hide",
                ]
            ) {
                SettingsToggle(isOn: $settings.hideNotchInFullScreen)
            },
            SettingsEntry(
                "hideNotchFullScreenApps.add",
                title: "Hide in selected apps",
                detail: settings.hideNotchFullScreenApps.isEmpty
                    ? "Choose apps such as QuickTime Player or VLC."
                    : "\(settings.hideNotchFullScreenApps.count) selected",
                keywords: [
                    "fullscreen", "quicktime", "vlc", "player", "movie",
                    "video",
                ]
            ) {
                Button("Add") { addFullScreenHideApps() }
                    .controlSize(.small)
                    .settingsButton()
            },
        ]
            + settings.hideNotchFullScreenApps.map { bundleID in
                SettingsEntry(
                    "hideNotchFullScreenApps.\(bundleID)",
                    title: FullScreenDetection.displayName(bundleID: bundleID),
                    detail: bundleID,
                    keywords: [
                        "fullscreen", "full screen", "hide",
                        FullScreenDetection.displayName(bundleID: bundleID)
                            .lowercased(),
                    ]
                ) {
                    Button("Remove") {
                        settings.removeHideNotchFullScreenApp(bundleID)
                    }
                    .controlSize(.small)
                    .settingsButton()
                }
            }
    }

    private func addFullScreenHideApps() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Add"
        panel.message =
            "Choose apps that should hide the notch when they are full screen."
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let id = FullScreenDetection.bundleIdentifier(at: url) {
                settings.addHideNotchFullScreenApp(id)
            }
        }
    }

    //     private var spotifyAccountDetail: String {
    //         if let error = spotifyLibrary.error, error != .canceled {
    //             return error.settingsMessage
    //         }
    //         if spotifyLibrary.isAuthorizing {
    //             return "Waiting for Spotify to finish signing in."
    //         }
    //         if spotifyLibrary.isAuthenticated {
    //             return "Signed in. The like button can save to Liked Songs."
    //         }
    //         if SpotifyConfig.resolvedClientID.isEmpty {
    //             return SpotifyLibraryError.missingClientID.settingsMessage
    //         }
    //         return "Sign in with Spotify to save tracks from the notch."
    //     }

    private var mediaGroups: [SettingsGroup] {
        [
            SettingsGroup(
                page: .media,
                title: "Player Toolbar",
                note:
                    "The row under the progress bar. Right-click it to customise. The heart only works in Music.",
                accessory: AnyView(
                    MediaToolbarLiveRow(items: settings.mediaToolbarItems)
                ),
                entries: [
                    SettingsEntry(
                        "mediaToolbarItems",
                        title: "Customise toolbar",
                        detail: "Add, remove and rearrange playback controls.",
                        keywords: [
                            "toolbar", "customise", "customize", "buttons",
                            "heart", "favourite", "favorite", "like", "skip",
                            "live", "playback", "layout",
                        ]
                    ) {
                        Button("Customise...") {
                            MediaToolbarEditorOpener.shared.open()
                        }
                        .controlSize(.small)
                        .settingsButton(prominent: true)
                    }
                    //                     SettingsEntry(
                    //                         "spotifyLibraryAccount",
                    //                         title: "Spotify",
                    //                         detail: spotifyAccountDetail,
                    //                         keywords: [
                    //                             "spotify", "connect", "login", "sign in", "oauth",
                    //                             "like",
                    //                         ]
                    //                     ) {
                    //                         if spotifyLibrary.isAuthorizing {
                    //                             ProgressView()
                    //                                 .controlSize(.small)
                    //                         } else if spotifyLibrary.isAuthenticated {
                    //                             Button("Sign Out") {
                    //                                 spotifyLibrary.disconnect()
                    //                             }
                    //                             .controlSize(.small)
                    //                             .settingsButton()
                    //                         } else {
                    //                             Button("Sign In") {
                    //                                 spotifyLibrary.connect()
                    //                             }
                    //                             .controlSize(.small)
                    //                             .settingsButton(prominent: true)
                    //                             .disabled(SpotifyConfig.resolvedClientID.isEmpty)
                    //                         }
                    //                     },
                ]
            ),
            SettingsGroup(
                page: .media,
                title: "Artists",
                note:
                    "Spotify only reports the first artist to macOS. Loffty can look up the full list over the network.",
                entries: [
                    SettingsEntry(
                        "artistEnrichment",
                        title: "Spotify artists",
                        keywords: ["network", "wifi", "lookup", "featuring"]
                    ) {
                        Picker("", selection: $settings.artistEnrichment) {
                            ForEach(ArtistEnrichmentMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .controlSize(.small)
                        .fixedSize()
                    }
                ]
            ),
            SettingsGroup(
                page: .media,
                title: "Player Badge",
                note:
                    "The badge shows the icon of the app that is playing on top of the album cover. For browser videos, a website icon appears next to it. That needs Automation access for the browser.",
                entries: [
                    SettingsEntry(
                        "playerBadgeExpanded",
                        title: "Expanded notch",
                        keywords: ["badge", "app icon"]
                    ) {
                        SettingsToggle(isOn: $settings.playerBadgeExpanded)
                    },
                    SettingsEntry(
                        "playerBadgeCollapsed",
                        title: "Collapsed notch",
                        keywords: ["badge", "app icon"]
                    ) {
                        SettingsToggle(isOn: $settings.playerBadgeCollapsed)
                    },
                    SettingsEntry(
                        "playerBadgeLockScreen",
                        title: "Lock screen",
                        keywords: ["badge", "app icon"]
                    ) {
                        SettingsToggle(isOn: $settings.playerBadgeLockScreen)
                    },
                    SettingsEntry(
                        "playerBadgeAutomation",
                        title: "Browser automation",
                        detail:
                            "If you refused access for Firefox, Safari or Chrome, turn that app back on here.",
                        keywords: [
                            "permission", "privacy", "firefox", "safari",
                            "chrome", "website", "badge",
                        ]
                    ) {
                        Button("Open") {
                            PrivacyAccess.openAutomationSettings()
                        }
                        .controlSize(.small)
                        .settingsButton()
                    },
                ]
            ),
            SettingsGroup(
                page: .media,
                title: "Presentation",
                note:
                    "With scrolling off, long titles and artists truncate with an ellipsis.",
                entries: [
                    SettingsEntry(
                        "marqueeEnabled",
                        title: "Scroll long titles and artists",
                        keywords: ["marquee", "ticker", "ellipsis"]
                    ) {
                        SettingsToggle(isOn: $settings.marqueeEnabled)
                    },
                    SettingsEntry(
                        "showAlbum",
                        title: "Show album name",
                        keywords: ["record", "title"]
                    ) {
                        SettingsToggle(isOn: $settings.showAlbum)
                    },
                    SettingsEntry(
                        "showAirPlayButton",
                        title: "Show AirPlay button",
                        keywords: ["output", "speaker", "route"]
                    ) {
                        SettingsToggle(isOn: $settings.showAirPlayButton)
                    },
                    SettingsEntry(
                        "notchEdgeStyle",
                        title: "Notch outline",
                        detail: settings.notchEdgeStyle.detail,
                        keywords: [
                            "edge", "outline", "border", "line", "accent",
                            "colour", "color",
                        ]
                    ) {
                        Picker("", selection: $settings.notchEdgeStyle) {
                            ForEach(NotchEdgeStyle.allCases) { style in
                                Text(style.title).tag(style)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .controlSize(.small)
                        .fixedSize()
                    },
                    SettingsEntry(
                        "notchOutlineWhenNotFullScreen",
                        title: "Outline when not full screen",
                        detail:
                            "When off, the outline only appears in full screen.",
                        keywords: [
                            "edge", "outline", "border", "desktop",
                            "fullscreen", "full screen",
                        ],
                        isEnabled: settings.notchEdgeStyle != .off
                    ) {
                        SettingsToggle(
                            isOn: $settings.notchOutlineWhenNotFullScreen
                        )
                    },
                ]
            ),
            SettingsGroup(
                page: .media,
                title: "Soundwaves",
                note:
                    "Live soundwaves listen to system audio. macOS may ask for Screen & System Audio Recording.",
                entries: [
                    SettingsEntry(
                        "soundwaveMotion",
                        title: "Motion",
                        detail: settings.soundwaveMotion.detail,
                        keywords: [
                            "waveform", "bars", "visualiser", "live",
                            "decorative", "audio",
                        ]
                    ) {
                        Picker("", selection: $settings.soundwaveMotion) {
                            ForEach(SoundwaveMotion.allCases) { motion in
                                Text(motion.title).tag(motion)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .controlSize(.small)
                        .fixedSize()
                    },
                    SettingsEntry(
                        "soundwaveFeel",
                        title: "Feel",
                        detail: settings.soundwaveFeel.detail,
                        keywords: [
                            "waveform", "bars", "smooth", "snappy", "calm",
                        ],
                        isEnabled: settings.soundwaveMotion.showsAnimatedBars
                    ) {
                        Picker("", selection: $settings.soundwaveFeel) {
                            ForEach(SoundwaveFeel.allCases) { feel in
                                Text(feel.title).tag(feel)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .controlSize(.small)
                        .fixedSize()
                    },
                    SettingsEntry(
                        "soundwaveTone",
                        title: "Tone",
                        detail: settings.soundwaveTone.detail,
                        keywords: [
                            "waveform", "bass", "bright", "warm", "frequency",
                        ],
                        isEnabled: settings.soundwaveMotion.usesLiveAudio
                    ) {
                        Picker("", selection: $settings.soundwaveTone) {
                            ForEach(SoundwaveTone.allCases) { tone in
                                Text(tone.title).tag(tone)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .controlSize(.small)
                        .fixedSize()
                    },
                    SettingsEntry(
                        "collapsedWaveformsAccent",
                        title: "Tint with album colour",
                        detail: "Uses the accent colour of the album cover.",
                        keywords: ["waveform", "colour", "color", "accent"],
                        isEnabled: settings.soundwaveMotion.showsAnimatedBars
                    ) {
                        SettingsToggle(isOn: $settings.collapsedWaveformsAccent)
                    },
                ]
            ),
        ]
    }

    private var overlayGroups: [SettingsGroup] {
        [
            SettingsGroup(
                page: .sensory,
                title: "Volume & Brightness",
                note:
                    "Replacing the system HUD requires Accessibility access in System Settings > Privacy & Security.",
                entries: [
                    SettingsEntry(
                        "replaceSystemHUD",
                        title: "Replace system HUDs",
                        keywords: ["volume", "brightness", "accessibility"]
                    ) {
                        SettingsToggle(isOn: $settings.replaceSystemHUD)
                    },
                    SettingsEntry(
                        "brightnessHUD",
                        title: "Show brightness overlay",
                        keywords: ["screen", "display", "dim"],
                        isEnabled: settings.replaceSystemHUD
                    ) {
                        SettingsToggle(isOn: $settings.brightnessHUD)
                    },
                    SettingsEntry(
                        "brightnessHUDShownOnAuto",
                        title: "Show automatic brightness adjustments",
                        keywords: ["screen", "display", "dim"],
                        isEnabled: settings.brightnessHUD
                    ) {
                        SettingsToggle(
                            isOn: $settings.brightnessHUDShownOnAutoAdjust
                        )
                    },
                ]
            ),
            SettingsGroup(
                page: .battery,
                title: "Battery",
                note:
                    "Appears as a drop-down chip when the charger is plugged in or the battery runs low.",
                entries: [
                    SettingsEntry(
                        "batteryHUD",
                        title: "Battery overlay",
                        keywords: ["charging", "power", "percentage", "chip"]
                    ) {
                        SettingsToggle(isOn: $settings.batteryHUD)
                    }
                ]
            ),
            SettingsGroup(
                page: .accessories,
                title: "Bluetooth",
                note:
                    "Takes over the side of the notch when a device connects or disconnects.",
                entries: [
                    SettingsEntry(
                        "bluetoothHUD",
                        title: "Bluetooth overlay",
                        keywords: [
                            "airpods", "headphones", "device", "connection",
                        ]
                    ) {
                        SettingsToggle(isOn: $settings.bluetoothHUD)
                    }
                ]
            ),
            SettingsGroup(
                page: .focus,
                title: "Focus",
                note:
                    "Shows the current Focus mode on the side of the notch when it changes.",
                entries: [
                    SettingsEntry(
                        "focusHUD",
                        title: "Focus overlay",
                        keywords: [
                            "do not disturb", "dnd", "sleep", "work",
                        ]
                    ) {
                        SettingsToggle(isOn: $settings.focusHUD)
                    }
                ]
            ),
            SettingsGroup(
                page: .airDrop,
                title: "AirDrop",
                note:
                    "Drop a file on the notch to start sending it. Incoming transfers appear there too.",
                entries: [
                    SettingsEntry(
                        "airDropHUD",
                        title: "AirDrop in notch",
                        keywords: ["drag", "drop", "share", "send", "files"]
                    ) {
                        SettingsToggle(isOn: $settings.airDropHUD)
                    }
                ]
            ),
            SettingsGroup(
                page: .notifications,
                title: "Notifications",
                note:
                    "Incoming Messages, WhatsApp and Discord notifications appear on the notch. Turn off Desktop for those apps to hide the system banner. Accessibility is required; Full Disk Access is needed when banners are off.",
                entries: [
                    SettingsEntry(
                        "notificationsHUD",
                        title: "Notifications in notch",
                        keywords: [
                            "messages", "whatsapp", "discord", "reply",
                            "banner",
                        ]
                    ) {
                        SettingsToggle(isOn: $settings.notificationsHUD)
                    },
                    SettingsEntry(
                        "notificationMessages",
                        title: "Messages",
                        keywords: ["imessage", "sms", "chat"],
                        isEnabled: settings.notificationsHUD
                    ) {
                        SettingsToggle(isOn: $settings.notificationMessages)
                    },
                    SettingsEntry(
                        "notificationWhatsApp",
                        title: "WhatsApp",
                        keywords: ["chat", "reply"],
                        isEnabled: settings.notificationsHUD
                    ) {
                        SettingsToggle(isOn: $settings.notificationWhatsApp)
                    },
                    SettingsEntry(
                        "notificationDiscord",
                        title: "Discord",
                        keywords: ["chat", "reply"],
                        isEnabled: settings.notificationsHUD
                    ) {
                        SettingsToggle(isOn: $settings.notificationDiscord)
                    },
                    SettingsEntry(
                        "notificationsHUDDismissDelay",
                        title: "Notification dismiss delay",
                        keywords: [
                            "messages", "whatsapp", "discord", "reply",
                            "banner", "dismiss",
                        ],
                        isEnabled: settings.notificationsHUD
                    ) {
                        HStack(spacing: 10) {
                            SettingsSlider(
                                value: $settings.notificationsHUDDismissDelay,
                                range: 0.5...5,
                                step: 0.25
                            )
                            .frame(width: 120)
                            Text(
                                String(
                                    format: "%.2fs",
                                    settings.notificationsHUDDismissDelay
                                )
                            )
                            .font(.system(size: 11.5))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 40, alignment: .trailing)
                        }
                    },
                    SettingsEntry(
                        "notificationFullDiskAccess",
                        title: "Full Disk Access",
                        detail: NotificationDatabaseReader.canReadDatabase()
                            ? "Granted. Loffty can read hidden notifications."
                            : "Needed to read notifications when banners are hidden.",
                        keywords: ["permission", "privacy", "database"]
                    ) {
                        if NotificationDatabaseReader.canReadDatabase() {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.secondary)
                        } else {
                            Button("Open") {
                                PrivacyAccess.openFullDiskAccessSettings()
                            }
                            .controlSize(.small)
                            .settingsButton()
                        }
                    },
                ]
            ),
            SettingsGroup(
                page: .notifications,
                title: "System banners",
                note:
                    "Keep Allow Notifications and Notification Centre on. Turning off Desktop hides the system banner so the notch can show them instead.",
                entries: notificationBannerEntries
            ),
        ]
    }

    private var notificationBannerEntries: [SettingsEntry] {
        _ = notificationPrefsStamp
        return NotificationApp.allCases.map { app in
            let hidden = NotificationStyleCheck.hidesSystemBanner(for: app)
            return SettingsEntry(
                "notificationAlertStyle.\(app.rawValue)",
                title: app.displayName,
                detail: hidden
                    ? "Desktop is off"
                    : "Turn off Desktop",
                keywords: [
                    "banner", "desktop", "alert style",
                    app.displayName.lowercased(),
                ],
                isEnabled: settings.notificationsHUD
            ) {
                if hidden {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.secondary)
                } else {
                    Button("Open") {
                        NotificationSettingsLink.openNotificationSettings(
                            for: app
                        )
                    }
                    .controlSize(.small)
                    .settingsButton()
                }
            }
        }
    }

    private var lockScreenGroups: [SettingsGroup] {
        [
            SettingsGroup(
                page: .lockScreen,
                title: "Notch",
                note:
                    "Expanding on the lock screen never steals focus from the password field.",
                entries: [
                    SettingsEntry(
                        "lockScreenNotch",
                        title: "Show notch on lock screen",
                        keywords: ["locked", "login window"]
                    ) {
                        SettingsToggle(isOn: $settings.lockScreenNotch)
                    },
                    SettingsEntry(
                        "lockScreenExpandNotch",
                        title: "Allow expanding on hover",
                        keywords: ["expand", "hover", "open"],
                        isEnabled: settings.lockScreenNotch
                    ) {
                        SettingsToggle(isOn: $settings.lockScreenExpandNotch)
                    },
                ]
            ),
            SettingsGroup(
                page: .lockScreen,
                title: "Artwork",
                entries: [
                    SettingsEntry(
                        "lockScreenFullScreenArt",
                        title: "Expand album artwork",
                        keywords: ["cover", "full screen", "art"]
                    ) {
                        SettingsToggle(isOn: $settings.lockScreenFullScreenArt)
                    },
                    SettingsEntry(
                        "lockScreenWaveforms",
                        title: "Show soundwaves",
                        detail:
                            "Uses the motion, feel, and tone from Media.",
                        keywords: ["waveform", "bars", "visualiser"]
                    ) {
                        SettingsToggle(isOn: $settings.lockScreenWaveforms)
                    },
                    SettingsEntry(
                        "lockScreenWaveformsAccent",
                        title: "Tint soundwaves",
                        keywords: ["waveform", "colour", "color", "accent"],
                        isEnabled: settings.lockScreenWaveforms
                    ) {
                        SettingsToggle(
                            isOn: $settings.lockScreenWaveformsAccent
                        )
                    },
                ]
            ),
            SettingsGroup(
                page: .lockScreen,
                title: "Widget",
                entries: [
                    SettingsEntry(
                        "movableWidget",
                        title: "Allow moving the widget",
                        keywords: ["drag", "position", "place"]
                    ) {
                        SettingsToggle(isOn: $settings.movableWidget)
                    },
                    SettingsEntry(
                        "resetWidgetPosition",
                        title: "Reset widget position",
                        detail: "Puts the widget back in the centre.",
                        keywords: ["default", "centre", "center"]
                    ) {
                        Button("Reset") { settings.resetWidgetPosition() }
                            .controlSize(.small)
                            .settingsButton()
                    },
                ]
            ),
            SettingsGroup(
                page: .lockScreen,
                title: "Accessories",
                note:
                    "Drag chips in the mock to reorder or move the row. Dimmed chips are turned off. Reset restores the default layout.",
                accessory: AnyView(LockAccessoriesLayoutMock()),
                entries: [
                    SettingsEntry(
                        "lockScreenWeatherAccessory",
                        title: "Weather",
                        keywords: ["forecast", "temperature", "chip"]
                    ) {
                        SettingsToggle(
                            isOn: $settings.lockScreenWeatherAccessory
                        )
                    },
                    SettingsEntry(
                        "lockScreenBluetoothAccessory",
                        title: "Bluetooth",
                        keywords: ["devices", "headphones", "chip"]
                    ) {
                        SettingsToggle(
                            isOn: $settings.lockScreenBluetoothAccessory
                        )
                    },
                    SettingsEntry(
                        "lockScreenBatteryAccessory",
                        title: "Battery",
                        keywords: ["power", "charge", "chip"]
                    ) {
                        SettingsToggle(
                            isOn: $settings.lockScreenBatteryAccessory
                        )
                    },
                    SettingsEntry(
                        "lockScreenFocusAccessory",
                        title: "Focus",
                        keywords: ["dnd", "do not disturb", "chip"]
                    ) {
                        SettingsToggle(
                            isOn: $settings.lockScreenFocusAccessory
                        )
                    },
                    SettingsEntry(
                        "resetLockScreenAccessoriesLayout",
                        title: "Reset layout",
                        detail: "Default order and position under the clock.",
                        keywords: ["default", "reset", "accessories", "order"]
                    ) {
                        Button("Reset") {
                            settings.resetLockScreenAccessoriesLayout()
                        }
                        .controlSize(.small)
                        .settingsButton()
                    },
                ]
            ),
            SettingsGroup(
                page: .lockScreen,
                title: "Weather chip",
                entries: [
                    SettingsEntry(
                        "lockScreenWeatherShowLocation",
                        title: "Show place name",
                        keywords: ["city", "locality"],
                        isEnabled: settings.lockScreenWeatherAccessory
                    ) {
                        SettingsToggle(
                            isOn: $settings.lockScreenWeatherShowLocation
                        )
                    },
                    SettingsEntry(
                        "lockScreenWeatherShowCondition",
                        title: "Show condition",
                        keywords: ["clear", "rain", "cloudy"],
                        isEnabled: settings.lockScreenWeatherAccessory
                    ) {
                        SettingsToggle(
                            isOn: $settings.lockScreenWeatherShowCondition
                        )
                    },
                    SettingsEntry(
                        "lockScreenWeatherShowHighLow",
                        title: "Show high and low",
                        keywords: ["max", "min"],
                        isEnabled: settings.lockScreenWeatherAccessory
                    ) {
                        SettingsToggle(
                            isOn: $settings.lockScreenWeatherShowHighLow
                        )
                    },
                    SettingsEntry(
                        "lockScreenWeatherShowUV",
                        title: "Show UV index",
                        keywords: ["sun"],
                        isEnabled: settings.lockScreenWeatherAccessory
                    ) {
                        SettingsToggle(isOn: $settings.lockScreenWeatherShowUV)
                    },
                    SettingsEntry(
                        "lockScreenWeatherShowWind",
                        title: "Show wind",
                        keywords: ["breeze"],
                        isEnabled: settings.lockScreenWeatherAccessory
                    ) {
                        SettingsToggle(
                            isOn: $settings.lockScreenWeatherShowWind
                        )
                    },
                    SettingsEntry(
                        "lockScreenWeatherShowPrecip",
                        title: "Show rain chance",
                        keywords: ["precip", "precipitation", "rain"],
                        isEnabled: settings.lockScreenWeatherAccessory
                    ) {
                        SettingsToggle(
                            isOn: $settings.lockScreenWeatherShowPrecip
                        )
                    },
                    SettingsEntry(
                        "lockScreenWeatherShowGraph",
                        title: "Show graph",
                        keywords: ["sparkline", "chart", "trend"],
                        isEnabled: settings.lockScreenWeatherAccessory
                    ) {
                        SettingsToggle(
                            isOn: $settings.lockScreenWeatherShowGraph
                        )
                    },
                    SettingsEntry(
                        "lockScreenWeatherGraphKind",
                        title: "Graph shows",
                        keywords: [
                            "temperature", "precipitation", "rain", "chart",
                        ],
                        isEnabled: settings.lockScreenWeatherAccessory
                            && settings.lockScreenWeatherShowGraph
                    ) {
                        SettingsMenu(
                            selection: $settings.lockScreenWeatherGraphKind
                        ) {
                            ForEach(LockScreenWeatherGraphKind.allCases) {
                                kind in
                                Text(kind.title).tag(kind)
                            }
                        }
                    },
                    SettingsEntry(
                        "lockScreenWeatherShowGraphLabels",
                        title: "Show graph labels",
                        detail: "Hours and range on the sparkline.",
                        keywords: ["labels", "hours", "axis", "chart"],
                        isEnabled: settings.lockScreenWeatherAccessory
                            && settings.lockScreenWeatherShowGraph
                    ) {
                        SettingsToggle(
                            isOn: $settings.lockScreenWeatherShowGraphLabels
                        )
                    },
                ]
            ),
            SettingsGroup(
                page: .lockScreen,
                title: "Other chips",
                entries: [
                    SettingsEntry(
                        "lockScreenBluetoothShowCount",
                        title: "Bluetooth device count",
                        detail:
                            "Show +N when more than one device is connected.",
                        keywords: ["airpods", "devices"],
                        isEnabled: settings.lockScreenBluetoothAccessory
                    ) {
                        SettingsToggle(
                            isOn: $settings.lockScreenBluetoothShowCount
                        )
                    },
                    SettingsEntry(
                        "lockScreenBatteryShowCharging",
                        title: "Battery charging status",
                        keywords: ["adapter", "power", "charge"],
                        isEnabled: settings.lockScreenBatteryAccessory
                    ) {
                        SettingsToggle(
                            isOn: $settings.lockScreenBatteryShowCharging
                        )
                    },
                ]
            ),
        ]
    }

    private var weatherGroups: [SettingsGroup] {
        [
            SettingsGroup(
                page: .weather,
                title: "Weather",
                note:
                    "Weather uses your location and Open-Meteo. Because Loffty lives in the menu bar, macOS needs a regular window to show the Location prompt.",
                entries: [
                    SettingsEntry(
                        "weatherEnabled",
                        title: "Weather in the notch",
                        keywords: ["forecast", "expanded", "page"]
                    ) {
                        SettingsToggle(isOn: $settings.weatherEnabled)
                    },
                    SettingsEntry(
                        "weatherIdleExpand",
                        title: "When nothing is playing",
                        detail: "Shown when you expand the idle notch.",
                        keywords: ["idle", "default", "page"],
                        isEnabled: settings.weatherEnabled
                    ) {
                        SettingsMenu(selection: $settings.weatherIdleExpand) {
                            ForEach(WeatherIdleExpand.allCases) { option in
                                Text(option.title).tag(option)
                            }
                        }
                    },
                    SettingsEntry(
                        "weatherSwipeEnabled",
                        title: "Swipe between music and weather",
                        detail: "Two-finger swipe on the expanded notch.",
                        keywords: ["trackpad", "gesture", "page"],
                        isEnabled: settings.weatherEnabled
                    ) {
                        SettingsToggle(isOn: $settings.weatherSwipeEnabled)
                    },
                    SettingsEntry(
                        "weatherLocation",
                        title: "Location",
                        detail: "Allow shows the macOS Location prompt.",
                        keywords: ["permission", "gps", "allow"],
                        isEnabled: settings.weatherEnabled
                    ) {
                        HStack(spacing: 6) {
                            Button("Allow") {
                                WeatherController.shared.requestAccessFromUser()
                            }
                            .controlSize(.small)
                            .settingsButton(prominent: true)
                            Button("Settings") {
                                PrivacyAccess.openLocationSettings()
                            }
                            .controlSize(.small)
                            .settingsButton()
                        }
                    },
                ]
            ),
            SettingsGroup(
                page: .weather,
                title: "Location",
                entries: [
                    SettingsEntry(
                        "weatherLocationMode",
                        title: "Weather location",
                        detail: "Use your current location or a fixed place.",
                        keywords: ["city", "address", "manual", "gps"],
                        isEnabled: settings.weatherEnabled
                    ) {
                        SettingsMenu(selection: $settings.weatherLocationMode) {
                            ForEach(WeatherLocationMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                    },
                    SettingsEntry(
                        "weatherManualLocation",
                        title: "Fixed place",
                        detail: "Enter a city, address, or postal code.",
                        keywords: ["city", "address", "place"],
                        isEnabled: settings.weatherEnabled
                            && settings.weatherLocationMode == .manual
                    ) {
                        HStack(spacing: 6) {
                            TextField(
                                "City or address",
                                text: $settings.weatherManualLocation
                            )
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 150)
                            Button("Set") {
                                WeatherController.shared.refreshManualLocation()
                            }
                            .controlSize(.small)
                            .settingsButton(prominent: true)
                        }
                    },
                ]
            ),
            SettingsGroup(
                page: .weather,
                title: "Slide order",
                note: "Choose which weather view appears on each slide.",
                entries: settings.weatherSectionOrder.enumerated().map {
                    index,
                    section in
                    SettingsEntry(
                        "weatherSectionOrder.\(section.rawValue)",
                        title: section.title,
                        detail: "Slide \(index + 1)",
                        keywords: ["reorder", "slides", "sections"],
                        isEnabled: settings.weatherEnabled
                    ) {
                        HStack(spacing: 4) {
                            Button {
                                settings.moveWeatherSection(section, offset: -1)
                            } label: {
                                Image(systemName: "chevron.up")
                            }
                            .disabled(index == 0)
                            Button {
                                settings.moveWeatherSection(section, offset: 1)
                            } label: {
                                Image(systemName: "chevron.down")
                            }
                            .disabled(
                                index == settings.weatherSectionOrder.count - 1
                            )
                        }
                        .controlSize(.small)
                    }
                }
            ),
            SettingsGroup(
                page: .weather,
                title: "Units",
                entries: [
                    SettingsEntry(
                        "weatherTemperatureUnit",
                        title: "Temperature",
                        keywords: ["celsius", "fahrenheit", "degrees"],
                        isEnabled: settings.weatherEnabled
                    ) {
                        SettingsMenu(
                            selection: $settings.weatherTemperatureUnit
                        ) {
                            ForEach(WeatherTemperatureUnit.allCases) { unit in
                                Text(unit.title).tag(unit)
                            }
                        }
                    },
                    SettingsEntry(
                        "weatherWindUnit",
                        title: "Wind",
                        keywords: ["kmh", "mph", "speed"],
                        isEnabled: settings.weatherEnabled
                    ) {
                        SettingsMenu(selection: $settings.weatherWindUnit) {
                            ForEach(WeatherWindUnit.allCases) { unit in
                                Text(unit.title).tag(unit)
                            }
                        }
                    },
                ]
            ),
            SettingsGroup(
                page: .weather,
                title: "Details",
                entries: [
                    SettingsEntry(
                        "weatherShowLocation",
                        title: "Show place name",
                        keywords: ["city", "locality"],
                        isEnabled: settings.weatherEnabled
                    ) {
                        SettingsToggle(isOn: $settings.weatherShowLocation)
                    },
                    SettingsEntry(
                        "weatherShowHighLow",
                        title: "Show high and low",
                        keywords: ["max", "min", "range"],
                        isEnabled: settings.weatherEnabled
                    ) {
                        SettingsToggle(isOn: $settings.weatherShowHighLow)
                    },
                    SettingsEntry(
                        "weatherShowUV",
                        title: "Show UV index",
                        keywords: ["sun", "index"],
                        isEnabled: settings.weatherEnabled
                    ) {
                        SettingsToggle(isOn: $settings.weatherShowUV)
                    },
                    SettingsEntry(
                        "weatherShowWind",
                        title: "Show wind speed",
                        keywords: ["breeze"],
                        isEnabled: settings.weatherEnabled
                    ) {
                        SettingsToggle(isOn: $settings.weatherShowWind)
                    },
                ]
            ),
            SettingsGroup(
                page: .weather,
                title: "Hourly",
                entries: [
                    SettingsEntry(
                        "weatherShowHourly",
                        title: "Show hourly forecast",
                        keywords: ["hours", "timeline"],
                        isEnabled: settings.weatherEnabled
                    ) {
                        SettingsToggle(isOn: $settings.weatherShowHourly)
                    },
                    SettingsEntry(
                        "weatherHourCount",
                        title: "Hours shown",
                        keywords: ["count", "columns"],
                        isEnabled: settings.weatherEnabled
                            && settings.weatherShowHourly
                    ) {
                        SettingsMenu(
                            selection: Binding(
                                get: { settings.weatherHourCount },
                                set: { settings.weatherHourCount = $0 }
                            )
                        ) {
                            ForEach([3, 4, 5, 6], id: \.self) { count in
                                Text("\(count)").tag(count)
                            }
                        }
                    },
                    SettingsEntry(
                        "weatherShowPrecip",
                        title: "Show rain chance",
                        keywords: ["precipitation", "percent"],
                        isEnabled: settings.weatherEnabled
                            && settings.weatherShowHourly
                    ) {
                        SettingsToggle(isOn: $settings.weatherShowPrecip)
                    },
                ]
            ),
            SettingsGroup(
                page: .weather,
                title: "Refresh",
                entries: [
                    SettingsEntry(
                        "weatherRefreshMinutes",
                        title: "Update interval",
                        keywords: ["refresh", "minutes", "cache"],
                        isEnabled: settings.weatherEnabled
                    ) {
                        SettingsMenu(
                            selection: Binding(
                                get: { settings.weatherRefreshMinutes },
                                set: { settings.weatherRefreshMinutes = $0 }
                            )
                        ) {
                            ForEach([10.0, 15.0, 30.0, 60.0], id: \.self) {
                                minutes in
                                Text("\(Int(minutes)) min").tag(minutes)
                            }
                        }
                    }
                ]
            ),
        ]
    }

    private var updateGroups: [SettingsGroup] {
        [
            SettingsGroup(
                page: .updates,
                title: "Updates",
                note:
                    "Updates come from GitHub Releases and are verified with SHA-256 and Ed25519. Because Loffty is not notarised, macOS may ask you to allow a new build once after an update.",
                entries: [
                    SettingsEntry(
                        "automaticUpdates",
                        title: "Check automatically",
                        detail: "Once a day, in the background.",
                        keywords: ["auto", "daily", "background"]
                    ) {
                        SettingsToggle(isOn: $settings.automaticUpdates)
                    },
                    SettingsEntry(
                        "checkForUpdates",
                        title: "Version \(updater.currentVersion)",
                        detail: updateStatusText,
                        keywords: ["check", "install", "release", "download"]
                    ) {
                        HStack(spacing: 8) {
                            if isUpdateBusy {
                                ProgressView()
                                    .controlSize(.small)
                                    .scaleEffect(0.7)
                            }
                            if case .available(let release) = updater.state {
                                Button("Install \(release.version)") {
                                    updater.install(release)
                                }
                                .controlSize(.small)
                                .settingsButton(prominent: true)
                            } else {
                                Button("Check Now") {
                                    updater.checkForUpdatesNow()
                                }
                                .controlSize(.small)
                                .settingsButton()
                                .disabled(isUpdateBusy)
                            }
                        }
                    },
                ]
            )
        ]
    }

    private var isUpdateBusy: Bool {
        switch updater.state {
        case .checking, .downloading, .installing: true
        default: false
        }
    }

    private var updateStatusText: String {
        switch updater.state {
        case .idle: "Not checked yet"
        case .checking: "Checking..."
        case .upToDate: "Up to date"
        case .available(let release): "\(release.version) is available"
        case .downloading: "Downloading..."
        case .installing: "Installing..."
        case .failed(let message): message
        }
    }
}

private struct SidebarRow: View {
    let page: SettingsPage
    let isSelected: Bool
    let badge: String?
    let showsDot: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var scheme
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            decorated(
                HStack(spacing: 9) {
                    Image(systemName: page.symbol)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(isSelected ? Color.primary : page.tint)
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 18)
                    Text(page.title)
                        .font(
                            .system(
                                size: 13,
                                weight: isSelected ? .semibold : .regular
                            )
                        )
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if showsDot {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 6, height: 6)
                    }
                    if let badge {
                        Text(badge)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal, 10)
                .frame(height: 32)
            )
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
    }

    @ViewBuilder
    private func decorated(_ content: some View) -> some View {
        if isSelected {
            content.settingsSurface(
                shape,
                scheme: scheme,
                interactive: true,
                fallbackFill: SettingsChrome.selectionFill(scheme)
            )
        } else if hovering {
            content.background(shape.fill(SettingsChrome.hoverFill(scheme)))
        } else {
            content
        }
    }
}

private struct SettingsCard: View {
    let group: SettingsGroup
    let showsPage: Bool
    let showsNote: Bool

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(caption)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                if let accessory = group.accessory {
                    accessory
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 10)
                    if !group.entries.isEmpty {
                        Rectangle()
                            .fill(SettingsChrome.cardStroke(scheme))
                            .frame(height: 1)
                            .padding(.leading, 16)
                    }
                }
                ForEach(Array(group.entries.enumerated()), id: \.element.id) {
                    index,
                    entry in
                    if index > 0 {
                        Rectangle()
                            .fill(SettingsChrome.cardStroke(scheme))
                            .frame(height: 1)
                            .padding(.leading, 16)
                    }
                    SettingsRowView(entry: entry)
                }
            }
            .settingsSurface(shape, scheme: scheme)

            if showsNote, let note = group.note {
                Text(note)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
                    .padding(.top, 2)
            }
        }
    }

    private var caption: String {
        let text =
            showsPage
            ? "\(group.page.title) · \(group.title)"
            : group.title
        return text
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
    }
}

private struct SettingsRowView: View {
    let entry: SettingsEntry

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .font(.system(size: 13, weight: .medium))
                if let detail = entry.detail {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            entry.control
                .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .frame(minHeight: 46)
        .opacity(entry.isEnabled ? 1 : 0.4)
        .disabled(!entry.isEnabled)
    }
}

private struct SettingsToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Toggle("", isOn: $isOn)
            .labelsHidden()
            .toggleStyle(.switch)
            .sensoryFeedback(.selection, trigger: isOn)
    }
}

private struct SettingsMenu<Selection: Hashable, Content: View>: View {
    @Binding var selection: Selection
    @ViewBuilder var content: () -> Content

    var body: some View {
        Picker("", selection: $selection) {
            content()
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .controlSize(.small)
        .frame(width: 128)
    }
}

private struct SettingsSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double

    var body: some View {
        Slider(value: $value, in: range, step: step)
            .onChange(of: value) { _, _ in
                NSHapticFeedbackManager.defaultPerformer.perform(
                    .alignment,
                    performanceTime: .now
                )
            }
    }
}

private struct SearchField: View {
    @Binding var text: String

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            TextField("Search", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 30)
        .settingsSurface(shape, scheme: scheme, interactive: true)
        .onExitCommand { text = "" }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
    }
}

extension View {
    @ViewBuilder
    func settingsSurface<S: InsettableShape>(
        _ shape: S,
        scheme: ColorScheme,
        interactive: Bool = false,
        fallbackFill: Color? = nil
    ) -> some View {
        #if compiler(>=6.2)
            if #available(macOS 26.0, *) {
                self.glassEffect(
                    interactive ? .clear.interactive() : .clear,
                    in: shape
                )
            } else {
                settingsSurfaceFallback(
                    shape,
                    scheme: scheme,
                    fallbackFill: fallbackFill
                )
            }
        #else
            settingsSurfaceFallback(
                shape,
                scheme: scheme,
                fallbackFill: fallbackFill
            )
        #endif
    }

    @ViewBuilder
    private func settingsSurfaceFallback<S: InsettableShape>(
        _ shape: S,
        scheme: ColorScheme,
        fallbackFill: Color?
    ) -> some View {
        self
            .background(
                shape.fill(fallbackFill ?? SettingsChrome.cardFill(scheme))
            )
            .overlay(
                shape.strokeBorder(
                    SettingsChrome.cardStroke(scheme),
                    lineWidth: 1
                )
            )
    }

    @ViewBuilder
    func settingsButton(prominent: Bool = false) -> some View {
        #if compiler(>=6.2)
            if #available(macOS 26.0, *) {
                if prominent {
                    self.buttonStyle(.glassProminent)
                } else {
                    self.buttonStyle(.glass)
                }
            } else if prominent {
                self.buttonStyle(.borderedProminent)
            } else {
                self.buttonStyle(.bordered)
            }
        #else
            if prominent {
                self.buttonStyle(.borderedProminent)
            } else {
                self.buttonStyle(.bordered)
            }
        #endif
    }
}

struct GlassStack<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        #if compiler(>=6.2)
            if #available(macOS 26.0, *) {
                GlassEffectContainer(spacing: 0) { content }
            } else {
                content
            }
        #else
            content
        #endif
    }
}

enum SettingsChrome {
    static func cardFill(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color.white.opacity(0.06)
            : Color.white.opacity(0.42)
    }

    static func cardStroke(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color.white.opacity(0.10)
            : Color.black.opacity(0.05)
    }

    static func selectionFill(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color.white.opacity(0.14)
            : Color.white.opacity(0.62)
    }

    static func hoverFill(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color.white.opacity(0.055)
            : Color.black.opacity(0.04)
    }
}

struct VisualEffectBackground: NSViewRepresentable {
    let material: NSVisualEffectView.Material

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
    }
}
