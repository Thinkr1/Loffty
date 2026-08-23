//
//  NotificationNotchContent.swift
//  Loffty
//
//  Created by Pierre-Louis ML on 13/08/2026.
//

import SwiftUI

struct NotificationNotchContent: View {
    @ObservedObject var notifications: NotificationController
    let m: NotchMetrics
    @FocusState private var replyFocused: Bool

    var body: some View {
        Group {
            if notifications.isExpanded {
                expandedBody
            } else {
                compactBody
            }
        }
        .frame(width: m.width, height: m.height, alignment: .top)
        .overlay {
            if showsCompactReply {
                compactReplyButton
                    .position(replyCenter)
                    .transition(
                        .scale(scale: 0.72).combined(with: .opacity)
                    )
            }
        }
        .animation(
            notifications.isExpanded
                ? NotchViewModel.notchExpandSpring
                : NotchViewModel.notchCollapseSpring,
            value: notifications.isExpanded
        )
        .animation(NotchViewModel.notchExpandSpring, value: m.width)
        .animation(NotchViewModel.notchExpandSpring, value: m.height)
        .animation(NotchViewModel.notchExpandSpring, value: m.bottomRadius)
        .animation(NotchViewModel.notchExpandSpring, value: notifications.draft)
    }

    private var compactBody: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: m.notchH)

            Button(action: notifications.expand) {
                HStack(
                    alignment: .center,
                    spacing: NotificationLayout.compactRowSpacing
                ) {
                    NotificationAvatarView(
                        notification: notifications.current,
                        size: NotificationLayout.compactAvatar
                    )
                    VStack(alignment: .leading, spacing: 3) {
                        Text(notifications.current?.sender ?? "")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.78))
                            .lineLimit(1)
                        Text(notifications.current?.body ?? "")
                            .font(.system(size: 12.5, weight: .regular))
                            .foregroundStyle(.white.opacity(0.5))
                            .lineLimit(
                                NotificationLayout.compactMessageLines
                            )
                            .lineSpacing(-1)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(
                        .trailing,
                        NotificationLayout.replySize
                            + NotificationLayout.replyEdgePadding
                    )
                }
                .padding(
                    .horizontal,
                    NotificationLayout.compactHorizontalPadding
                )
                .padding(.top, NotificationLayout.compactTopPadding)
                .padding(.bottom, NotificationLayout.compactBottomPadding)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("See more")
        }
    }

    private var expandedBody: some View {
        VStack(
            alignment: .leading,
            spacing: NotificationLayout.expandedStackSpacing
        ) {
            HStack(alignment: .top, spacing: 10) {
                Button(action: notifications.openCurrent) {
                    NotificationAvatarView(
                        notification: notifications.current,
                        size: 36
                    )
                }
                .buttonStyle(NotchControlButtonStyle())

                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(notifications.current?.sender ?? "")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.78))
                            .lineLimit(1)
                        Spacer(minLength: 6)
                        TimelineView(.periodic(from: .now, by: 15)) { context in
                            Text(
                                NotificationBannerParser.relativeLabel(
                                    from: notifications.current?.deliveredAt
                                        ?? context.date,
                                    now: context.date
                                )
                            )
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(.white.opacity(0.32))
                        }
                    }
                    Text(notifications.current?.body ?? "")
                        .font(.system(size: 12.5, weight: .regular))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(NotificationLayout.compactMessageLines)
                        .lineSpacing(-1)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button(action: { notifications.dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white.opacity(0.45))
                        .frame(width: 16, height: 16)
                        .background(
                            Circle().fill(.white.opacity(0.08))
                        )
                }
                .buttonStyle(NotchControlButtonStyle())
                .help("Close")
            }
            if canReply {
                composer
            }
        }
        .padding(
            .horizontal,
            NotificationLayout.composerHorizontalPadding(topRadius: m.topRadius)
        )
        .padding(.top, m.notchH + NotificationLayout.expandedTopPadding)
        .padding(.bottom, NotificationLayout.composerInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            replyFocused = notifications.isReplying
        }
        .onChange(of: notifications.isReplying) { _, replying in
            replyFocused = replying
        }
        .onChange(of: replyFocused) { _, focused in
            if focused, canReply { notifications.beginReply() }
        }
    }

    private var composer: some View {
        HStack(spacing: 6) {
            TextField(
                "",
                text: $notifications.draft,
                prompt: Text(replyPrompt)
                    .foregroundStyle(.white.opacity(0.28)),
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .font(.system(size: 13, weight: .regular))
            .foregroundStyle(.white.opacity(0.78))
            .lineLimit(1...NotificationLayout.compactMessageLines)
            .focused($replyFocused)
            .focusEffectDisabled()
            .onSubmit(notifications.sendReply)

            Button(action: notifications.sendReply) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(
                        canSend
                            ? .white.opacity(0.95) : .white.opacity(0.32)
                    )
                    .frame(width: 26, height: 26)
                    .background(
                        Circle().fill(
                            canSend
                                ? Color(red: 0.20, green: 0.48, blue: 0.96)
                                : Color.white.opacity(0.10)
                        )
                    )
            }
            .buttonStyle(NotchControlButtonStyle())
            .disabled(!canSend)
            .help(replyActionHelp)
        }
        .padding(.leading, 14)
        .padding(.trailing, 4)
        .padding(.vertical, 5)
        .notificationGlass(composerShape, interactive: true)
    }

    private var compactReplyButton: some View {
        Button(action: notifications.beginReply) {
            Image(systemName: "arrowshape.turn.up.left.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.72))
                .frame(
                    width: NotificationLayout.replySize,
                    height: NotificationLayout.replySize
                )
                .contentShape(Circle())
        }
        .buttonStyle(NotchControlButtonStyle())
        .notificationGlass(Circle(), interactive: true)
        .help("Reply")
    }

    private var showsCompactReply: Bool {
        canReply && !notifications.isExpanded
    }

    private var canReply: Bool {
        notifications.current?.app.supportsReply ?? false
    }

    private var replyPrompt: String {
        notifications.current?.app == .whatsApp
            ? "Message (opens WhatsApp)" : "Reply"
    }

    private var replyActionHelp: String {
        notifications.current?.app == .whatsApp
            ? "Open WhatsApp with prefilled message" : "Send"
    }

    private var replyCenter: CGPoint {
        NotificationLayout.replyCenter(
            in: CGSize(width: m.width, height: m.height),
            topRadius: m.topRadius,
            bottomRadius: m.bottomRadius
        )
    }

    private var composerShape: UnevenRoundedRectangle {
        let height = NotificationLayout.composerHeight(
            draft: notifications.draft
        )
        let bottom = NotificationLayout.composerCornerRadius(
            islandBottomRadius: m.bottomRadius,
            height: height
        )
        let top = min(12, height / 2)
        return UnevenRoundedRectangle(
            topLeadingRadius: top,
            bottomLeadingRadius: bottom,
            bottomTrailingRadius: bottom,
            topTrailingRadius: top,
            style: .continuous
        )
    }

    private var canSend: Bool {
        !notifications.draft.trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty && !notifications.sending
    }
}

extension View {
    @ViewBuilder
    fileprivate func notificationGlass<S: InsettableShape>(
        _ shape: S,
        interactive: Bool = false
    ) -> some View {
        #if compiler(>=6.2)
            if #available(macOS 26.0, *) {
                self.glassEffect(
                    interactive ? .clear.interactive() : .clear,
                    in: shape
                )
            } else {
                notificationGlassFallback(shape)
            }
        #else
            notificationGlassFallback(shape)
        #endif
    }

    private func notificationGlassFallback<S: InsettableShape>(
        _ shape: S
    ) -> some View {
        self
            .background(shape.fill(Color.white.opacity(0.10)))
            .overlay {
                shape.strokeBorder(.white.opacity(0.08), lineWidth: 1)
            }
    }
}

struct NotificationAvatarView: View {
    let notification: NotchNotification?
    var size: CGFloat = 36

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            avatar
            if let note = notification {
                appBadge(note.app)
            }
        }
        .frame(width: size, height: size)
    }

    @ViewBuilder
    private var avatar: some View {
        if let data = notification?.avatar, let image = NSImage(data: data) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fill)
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else {
            Circle()
                .fill((notification?.app.accent ?? .white).opacity(0.32))
                .overlay {
                    Text(
                        NotificationBannerParser.initials(
                            from: notification?.sender ?? "?"
                        )
                    )
                    .font(
                        .system(
                            size: max(9, size * 0.34),
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(.white.opacity(0.72))
                }
                .frame(width: size, height: size)
        }
    }

    private func appBadge(_ app: NotificationApp) -> some View {
        let badge = max(11, size * 0.34)
        let radius = badge * 0.24
        return Group {
            if let icon = NotificationAppIcon.image(for: app) {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(app.accent)
                    Image(systemName: app.symbolName)
                        .font(.system(size: badge * 0.44, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(width: badge, height: badge)
        .clipShape(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(Color.black.opacity(0.45), lineWidth: 1)
        }
        .offset(x: 1, y: 1)
        .allowsHitTesting(false)
    }
}

enum NotificationAppIcon {
    private static var cache: [String: NSImage] = [:]

    static func image(for app: NotificationApp) -> NSImage? {
        for id in app.bundleIDs {
            if let cached = cache[id] { return cached }
            if let running = NSWorkspace.shared.runningApplications.first(
                where: { $0.bundleIdentifier == id }
            ), let icon = running.icon {
                cache[id] = icon
                return icon
            }
            if let url = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: id
            ) {
                let icon = NSWorkspace.shared.icon(forFile: url.path)
                cache[id] = icon
                return icon
            }
        }
        return nil
    }
}
