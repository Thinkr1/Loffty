//
//  MediaToolbarEditor.swift
//  Loffty
//
//  Created by Pierre-Louis ML on 20/08/2026.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class MediaToolbarEditorOpener {
    static let shared = MediaToolbarEditorOpener()

    func open() {
        let settingsOpen = SettingsOpener.shared.hostedWindow?.isVisible == true
        SettingsOpener.shared.hostedWindow?.orderOut(nil)
        MediaToolbarCustomizer.shared.begin(reopenSettings: settingsOpen)
    }

    func close() {
        MediaToolbarCustomizer.shared.end()
    }
}

struct MediaToolbarCustomizeChrome: View {
    @ObservedObject private var customizer = MediaToolbarCustomizer.shared

    var body: some View {
        VStack(spacing: 12) {
            Text(
                "Drag items into the toolbar to add them. Drag them out to remove them."
            )
            .font(.system(size: 11))
            .foregroundStyle(.white.opacity(0.55))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)

            palette
                .padding(10)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.white.opacity(0.06))
                )

            HStack {
                Button("Restore Defaults") {
                    customizer.restoreDefaults()
                }
                .controlSize(.small)
                .settingsButton()
                Spacer()
                Button("Done") {
                    MediaToolbarEditorOpener.shared.close()
                }
                .controlSize(.small)
                .settingsButton(prominent: true)
                .keyboardShortcut(.defaultAction)
            }
        }
        .contentShape(Rectangle())
        .overlay {
            Color.clear
                .contentShape(Rectangle())
                .allowsHitTesting(
                    customizer.isDragging && customizer.dragSource == .toolbar
                )
                .onDrop(
                    of: [.plainText, .text, .utf8PlainText],
                    delegate: MediaToolbarPaletteDropDelegate(
                        customizer: customizer
                    )
                )
        }
        .onExitCommand {
            MediaToolbarEditorOpener.shared.close()
        }
    }

    private var palette: some View {
        LazyVGrid(
            columns: [
                GridItem(.adaptive(minimum: 72), spacing: 8)
            ],
            spacing: 10
        ) {
            ForEach(MediaToolbarItem.palette) { item in
                MediaToolbarChip(item: item, compact: false, tint: .white)
                    .opacity(paletteOpacity(for: item))
                    .onDrag {
                        customizer.beginPaletteDrag(item)
                        return NSItemProvider(
                            object: item.rawValue as NSString
                        )
                    } preview: {
                        MediaToolbarChip(
                            item: item,
                            compact: true,
                            tint: .white
                        )
                    }
            }
        }
    }

    private func paletteOpacity(for item: MediaToolbarItem) -> Double {
        if item.isSpace { return 1 }
        return customizer.slots.contains(where: { $0.item == item })
            ? 0.42 : 1
    }
}

struct MediaToolbarCustomizeRow: View {
    @ObservedObject private var customizer = MediaToolbarCustomizer.shared
    @State private var frames: [UUID: CGRect] = [:]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(customizer.displaySlots) { slot in
                cell(slot)
            }
        }
        .coordinateSpace(name: "mediaToolbar")
        .onPreferenceChange(MediaToolbarSlotFrameKey.self) { frames = $0 }
        .animation(
            .interactiveSpring(response: 0.28, dampingFraction: 0.86),
            value: customizer.displaySlots.map(\.id)
        )
        .frame(maxWidth: .infinity, minHeight: 58)
        .overlay {
            Color.clear
                .contentShape(Rectangle())
                .allowsHitTesting(customizer.isDragging)
                .onDrop(
                    of: [.plainText, .text, .utf8PlainText],
                    delegate: MediaToolbarRowDropDelegate(
                        customizer: customizer,
                        frames: frames
                    )
                )
        }
    }

    @ViewBuilder
    private func cell(_ slot: MediaToolbarSlot) -> some View {
        if slot.id == MediaToolbarCustomizer.placeholderID {
            Color.clear
                .frame(
                    width: slot.item.isSpace ? 40 : 36,
                    height: 52
                )
                .background(slotFrameReader(slot.id))
        } else {
            MediaToolbarCustomizeItem(slot: slot)
                .onDrag {
                    if let index = customizer.slots.firstIndex(where: {
                        $0.id == slot.id
                    }) {
                        customizer.beginToolbarDrag(slot, at: index)
                    }
                    return NSItemProvider(
                        object: slot.item.rawValue as NSString
                    )
                } preview: {
                    MediaToolbarChip(
                        item: slot.item,
                        compact: true,
                        tint: .white
                    )
                }
                .background(slotFrameReader(slot.id))
        }
    }

    private func slotFrameReader(_ id: UUID) -> some View {
        GeometryReader { geo in
            Color.clear.preference(
                key: MediaToolbarSlotFrameKey.self,
                value: [
                    id: geo.frame(in: .named("mediaToolbar"))
                ]
            )
        }
    }
}

private struct MediaToolbarSlotFrameKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]

    static func reduce(
        value: inout [UUID: CGRect],
        nextValue: () -> [UUID: CGRect]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

private struct MediaToolbarRowDropDelegate: DropDelegate {
    let customizer: MediaToolbarCustomizer
    let frames: [UUID: CGRect]

    func validateDrop(info: DropInfo) -> Bool { true }

    func dropEntered(info: DropInfo) {
        update(info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        update(info)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        customizer.leaveToolbar()
    }

    func performDrop(info: DropInfo) -> Bool {
        customizer.commitToolbarDrop()
        return true
    }

    private func update(_ info: DropInfo) {
        let pairs = frames.map { (id: $0.key, frame: $0.value) }
        customizer.setInsertion(
            MediaToolbarCustomizer.insertionIndex(
                x: info.location.x,
                frames: pairs,
                placeholder: MediaToolbarCustomizer.placeholderID,
                current: customizer.insertionIndex
            )
        )
    }
}

private struct MediaToolbarPaletteDropDelegate: DropDelegate {
    let customizer: MediaToolbarCustomizer

    func validateDrop(info: DropInfo) -> Bool { true }

    func dropEntered(info: DropInfo) {
        customizer.hoverPalette()
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        customizer.hoverPalette()
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        customizer.commitPaletteDrop()
        return true
    }
}

private struct MediaToolbarCustomizeItem: View {
    let slot: MediaToolbarSlot

    var body: some View {
        VStack(spacing: 4) {
            MediaToolbarGlyph(item: slot.item, editing: true, tint: .white)
            Text(slot.item.title)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: slot.item.isSpace ? .infinity : 54)
        }
        .modifier(ToolbarJiggle(phase: phase))
        .help(slot.item.title)
    }

    private var phase: Double {
        Double(abs(slot.id.hashValue % 9)) * 0.018
    }
}

private struct ToolbarJiggle: ViewModifier {
    let phase: Double
    @State private var tipped = false

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(tipped ? 1.8 : -1.8))
            .animation(
                .easeInOut(duration: 0.14)
                    .repeatForever(autoreverses: true)
                    .delay(phase),
                value: tipped
            )
            .onAppear { tipped = true }
    }
}

struct MediaToolbarGlyph: View {
    let item: MediaToolbarItem
    var editing: Bool = false
    var tint: Color = .primary

    var body: some View {
        if item.isSpace {
            space
        } else {
            Image(systemName: item.symbol)
                .font(.system(size: item.controlSize, weight: .medium))
                .foregroundStyle(tint.opacity(dimmed ? 0.5 : 1))
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
                .help(item.title)
        }
    }

    private var dimmed: Bool {
        switch item {
        case .skipBack, .skipForward, .goLive, .like: true
        default: false
        }
    }

    @ViewBuilder
    private var space: some View {
        if editing {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(
                    style: StrokeStyle(lineWidth: 1, dash: [3, 2])
                )
                .foregroundStyle(tint.opacity(0.45))
                .frame(minWidth: 28, maxWidth: .infinity, minHeight: 12)
                .frame(height: 18)
                .help(item.title)
        } else {
            Spacer(minLength: 8)
        }
    }
}

struct MediaToolbarLiveRow: View {
    let items: [MediaToolbarItem]
    var tint: Color = .primary

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                MediaToolbarGlyph(item: item, tint: tint)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .animation(
            .smooth(duration: 0.25),
            value: items.map(\.rawValue)
        )
    }
}

struct MediaToolbarChip: View {
    let item: MediaToolbarItem
    var compact: Bool = true
    var tint: Color = .primary

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(tint.opacity(0.12))
                    .frame(width: compact ? 34 : 48, height: compact ? 28 : 34)
                if item.isSpace {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .strokeBorder(
                            style: StrokeStyle(lineWidth: 1, dash: [3, 2])
                        )
                        .frame(
                            width: compact ? 22 : 32,
                            height: compact ? 10 : 12
                        )
                        .foregroundStyle(tint.opacity(0.7))
                } else {
                    Image(systemName: item.symbol)
                        .font(
                            .system(
                                size: compact ? 12 : 14,
                                weight: .medium
                            )
                        )
                        .foregroundStyle(tint)
                }
            }
            if !compact {
                Text(item.title)
                    .font(.system(size: 10))
                    .foregroundStyle(tint.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(width: 76)
            }
        }
        .help(item.title)
    }
}
