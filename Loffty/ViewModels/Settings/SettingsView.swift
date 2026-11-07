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
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .searchable(text: $query, placement: .sidebar, prompt: "Search")
        .searchFocused($searchFocused)
        .frame(minWidth: 720, minHeight: 580)
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

    private var selection: Binding<SettingsPage?> {
        Binding(
            get: { isSearching ? nil : page },
            set: { newValue in
                guard let newValue else { return }
                query = ""
                storedPage = newValue.rawValue
            }
        )
    }

    private var sidebar: some View {
        List(selection: selection) {
            Section("General") {
                ForEach(pages(in: .app)) { sidebarRow($0) }
            }
            Section("Overlays") {
                ForEach(pages(in: .overlays)) { sidebarRow($0) }
            }
            Section {
                ForEach(pages(in: .footer)) { sidebarRow($0) }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit Loffty", systemImage: "power")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .keyboardShortcut("q", modifiers: .command)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
    }

    private func pages(in region: SettingsPage.Region) -> [SettingsPage] {
        SettingsPage.allCases.filter { $0.region == region }
    }

    @ViewBuilder
    private func sidebarRow(_ item: SettingsPage) -> some View {
        let label = Label {
            Text(item.title)
        } icon: {
            SettingsPageIcon(page: item)
        }
        .tag(item)
        if item == .updates {
            label.badge(
                updateAvailable
                    ? Text("Update").foregroundStyle(Color.accentColor)
                    : Text(updater.currentVersion)
            )
        } else {
            label
        }
    }

    private var updateAvailable: Bool {
        if case .available = updater.state { return true }
        return false
    }

    @ViewBuilder
    private var detail: some View {
        Group {
            if results.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                Form {
                    ForEach(results) { group in
                        SettingsSection(
                            group: group,
                            showsPage: isSearching,
                            showsNote: !isSearching
                        )
                    }
                }
                .formStyle(.grouped)
            }
        }
        .navigationTitle(isSearching ? "Search" : page.title)
        .id(isSearching ? "search" : storedPage)
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
                                .buttonStyle(.bordered)
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
                title: "Liquid Glass",
                note:
                    "By default the notch follows the Liquid Glass look chosen in System Settings -> Appearance. Turn this off to pick a look yourself.",
                entries: [
                    SettingsEntry(
                        "liquidGlassFollowsSystem",
                        title: "Match system Liquid Glass",
                        keywords: [
                            "glass", "liquid", "tint", "system", "appearance",
                            "slider", "automatic",
                        ]
                    ) {
                        SettingsToggle(isOn: $settings.liquidGlassFollowsSystem)
                    },
                    SettingsEntry(
                        "liquidGlassTintAmount",
                        title: "Tint",
                        keywords: [
                            "glass", "liquid", "tint", "slider", "clear",
                            "tinted", "dark", "opacity", "transparency",
                        ],
                        isEnabled: !settings.liquidGlassFollowsSystem
                    ) {
                        HStack(spacing: 8) {
                            Text("Clear")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            SettingsSlider(
                                value: $settings.liquidGlassTintAmount,
                                range: 0...1,
                                step: 0.1
                            )
                            .frame(width: 140)
                            Text("Tinted")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    },
                    SettingsEntry(
                        "liquidGlassTintWhenNotFullScreen",
                        title: "Notch glass",
                        keywords: [
                            "glass", "liquid", "tint", "clear", "regular",
                            "identity", "frosted", "material", "off",
                        ],
                        isEnabled: !settings.liquidGlassFollowsSystem
                    ) {
                        Picker(
                            "",
                            selection: $settings
                                .liquidGlassTintWhenNotFullScreen
                        ) {
                            ForEach(LiquidGlassTint.allCases) { tint in
                                Text(tint.title).tag(tint)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .controlSize(.small)
                        .fixedSize()
                    },
                    SettingsEntry(
                        "liquidGlassTintFullScreen",
                        title: "Notch glass in full screen",
                        keywords: [
                            "glass", "liquid", "tint", "clear", "regular",
                            "identity", "frosted", "fullscreen", "full screen",
                            "material", "off",
                        ],
                        isEnabled: !settings.liquidGlassFollowsSystem
                    ) {
                        Picker(
                            "",
                            selection: $settings.liquidGlassTintFullScreen
                        ) {
                            ForEach(LiquidGlassTint.allCases) { tint in
                                Text(tint.title).tag(tint)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .controlSize(.small)
                        .fixedSize()
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
                    .buttonStyle(.bordered)
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
                    .buttonStyle(.bordered)
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
                        .buttonStyle(.borderedProminent)
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
                    //                             .buttonStyle(.bordered)
                    //                         } else {
                    //                             Button("Sign In") {
                    //                                 spotifyLibrary.connect()
                    //                             }
                    //                             .controlSize(.small)
                    //                             .buttonStyle(.borderedProminent)
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
                        .buttonStyle(.bordered)
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
                        "flipArtworkOnTrackChange",
                        title: "Flip album cover on track change",
                        detail: "Not shown on the lock screen.",
                        keywords: [
                            "artwork", "animation", "flip", "rotate", "skip",
                        ]
                    ) {
                        SettingsToggle(
                            isOn: $settings.flipArtworkOnTrackChange
                        )
                    },
                    SettingsEntry(
                        "openPlayerOnArtworkClick",
                        title: "Click album cover to open",
                        detail:
                            "Opens the playing album in Music, or a recent track when nothing is playing.",
                        keywords: [
                            "artwork", "click", "tap", "open", "launch",
                            "recents", "idle",
                        ]
                    ) {
                        SettingsToggle(
                            isOn: $settings.openPlayerOnArtworkClick
                        )
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
                title: "When Nothing Is Playing",
                note:
                    "The expanded music notch can offer a play control and a few recent tracks. Recents are stored locally only while the option is on.",
                entries: [
                    SettingsEntry(
                        "idlePlayButton",
                        title: "Play button",
                        detail: "Opens Music or Spotify from the idle notch.",
                        keywords: [
                            "idle", "launch", "apple music", "spotify", "play",
                        ]
                    ) {
                        SettingsToggle(isOn: $settings.idlePlayButton)
                    },
                    SettingsEntry(
                        "idlePlayApp",
                        title: "Open",
                        detail:
                            "Automatic uses the last source, then Music, then Spotify.",
                        keywords: [
                            "idle", "music", "spotify", "default", "app",
                        ],
                        isEnabled: settings.idlePlayButton
                    ) {
                        SettingsMenu(selection: $settings.idlePlayApp) {
                            ForEach(IdlePlayApp.allCases) { app in
                                Text(app.title).tag(app)
                            }
                        }
                    },
                    SettingsEntry(
                        "idleRecentSuggestions",
                        title: "Recent tracks",
                        detail:
                            "Shows a few recently played songs from different apps.",
                        keywords: [
                            "idle", "history", "recents", "suggestions",
                            "cache",
                        ]
                    ) {
                        SettingsToggle(isOn: $settings.idleRecentSuggestions)
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
                            .buttonStyle(.bordered)
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
                    .buttonStyle(.bordered)
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
                note:
                    "The mock shows the widget on the lock wallpaper.",
                accessory: AnyView(LockWidgetGlassMock()),
                entries: [
                    SettingsEntry(
                        "lockScreenLiquidGlassTint",
                        title: "Liquid Glass",
                        keywords: [
                            "glass", "liquid", "tint", "clear", "regular",
                            "identity", "frosted", "material", "off",
                        ]
                    ) {
                        Picker(
                            "",
                            selection: $settings.lockScreenLiquidGlassTint
                        ) {
                            ForEach(LiquidGlassTint.allCases) { tint in
                                Text(tint.title).tag(tint)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .controlSize(.small)
                        .frame(maxWidth: 260)
                    },
                    SettingsEntry(
                        "lockScreenLiquidGlassColorTint",
                        title: "Glass colour",
                        keywords: [
                            "glass", "liquid", "tint", "colour", "color",
                            "none",
                        ],
                        isEnabled: settings.lockScreenLiquidGlassTint
                            != .identity
                    ) {
                        LockGlassColourControl()
                    },
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
                            .buttonStyle(.bordered)
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
                        .buttonStyle(.bordered)
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
                            .buttonStyle(.borderedProminent)
                            Button("Settings") {
                                PrivacyAccess.openLocationSettings()
                            }
                            .controlSize(.small)
                            .buttonStyle(.bordered)
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
                            .buttonStyle(.borderedProminent)
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
                                .buttonStyle(.borderedProminent)
                            } else {
                                Button("Check Now") {
                                    updater.checkForUpdatesNow()
                                }
                                .controlSize(.small)
                                .buttonStyle(.bordered)
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

private struct SettingsPageIcon: View {
    let page: SettingsPage

    @Environment(\.appearsActive) private var appearsActive

    var body: some View {
        Image(systemName: page.symbol)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 20, height: 20)
            .background(
                (page == .general ? Color.gray : page.tint).gradient,
                in: RoundedRectangle(cornerRadius: 5, style: .continuous)
            )
            .saturation(appearsActive ? 1 : 0.35)
            .animation(.easeInOut(duration: 0.2), value: appearsActive)
    }
}

private struct SettingsSection: View {
    let group: SettingsGroup
    let showsPage: Bool
    let showsNote: Bool

    var body: some View {
        Section {
            if let accessory = group.accessory {
                accessory
            }
            ForEach(group.entries) { entry in
                SettingsRowView(entry: entry)
            }
        } header: {
            Text(
                showsPage
                    ? "\(group.page.title) · \(group.title)" : group.title
            )
        } footer: {
            if showsNote, let note = group.note {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct SettingsRowView: View {
    let entry: SettingsEntry

    var body: some View {
        LabeledContent {
            entry.control
                .controlSize(.small)
        } label: {
            Text(entry.title)
            if let detail = entry.detail {
                Text(detail)
            }
        }
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

private struct LockGlassColourControl: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var draft: Color

    init() {
        _draft = State(
            initialValue: AppSettings.shared.lockScreenLiquidGlassColor
        )
    }

    var body: some View {
        HStack(spacing: 8) {
            Picker(
                "",
                selection: $settings.lockScreenLiquidGlassColorTint
            ) {
                ForEach(LiquidGlassColorTint.allCases) { tint in
                    Text(tint.title).tag(tint)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .controlSize(.small)
            .frame(maxWidth: 160)

            if settings.lockScreenLiquidGlassColorTint == .color {
                ColorPicker(
                    "",
                    selection: $draft,
                    supportsOpacity: true
                )
                .labelsHidden()
            }
        }
        .onChange(of: draft) { _, newValue in
            commit(newValue)
        }
    }

    private func commit(_ color: Color) {
        let encoded = LiquidGlassColorCodec.encode(color)
        DispatchQueue.main.async {
            let settings = AppSettings.shared
            guard
                encoded
                    != LiquidGlassColorCodec.encode(
                        settings.lockScreenLiquidGlassColor
                    )
            else { return }
            settings.lockScreenLiquidGlassColor = color
        }
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

extension View {
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
}
