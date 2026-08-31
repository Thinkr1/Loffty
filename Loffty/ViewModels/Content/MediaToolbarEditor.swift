//
//  MediaToolbarEditor.swift
//  Loffty
//
//  Created by Pierre-Louis ML on 20/08/2026.
//

import SwiftUI

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

struct MediaToolbarCustomizeSession: View {
    @ObservedObject private var customizer = MediaToolbarCustomizer.shared
    @State private var previewLocation: CGPoint?

    var body: some View {
        VStack(spacing: 0) {
            MediaToolbarCustomizeRow()
                .padding(.top, 2)
                .modifier(editDrag)
            MediaToolbarCustomizeChrome(editDrag: editDrag)
                .padding(.top, 8)
        }
        .coordinateSpace(name: MediaToolbarCustomizer.editSpace)
        .onPreferenceChange(MediaToolbarEditGeometryKey.self) {
            customizer.editGeometry = $0
        }
        .overlay {
            if customizer.isDragging,
                let item = customizer.draggingItem,
                let loc = previewLocation
            {
                MediaToolbarChip(item: item, compact: true, tint: .white)
                    .position(x: loc.x, y: loc.y)
                    .allowsHitTesting(false)
            }
        }
    }

    private var editDrag: MediaToolbarEditDragModifier {
        MediaToolbarEditDragModifier(
            customizer: customizer,
            previewLocation: $previewLocation
        )
    }
}

struct MediaToolbarEditDragModifier: ViewModifier {
    let customizer: MediaToolbarCustomizer
    @Binding var previewLocation: CGPoint?

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .highPriorityGesture(drag)
    }

    private var drag: some Gesture {
        DragGesture(
            minimumDistance: 3,
            coordinateSpace: .named(MediaToolbarCustomizer.editSpace)
        )
        .onChanged { value in
            if !customizer.isDragging {
                customizer.beginDrag(at: value.startLocation)
            }
            guard customizer.isDragging else { return }
            previewLocation = value.location
            customizer.updateDrag(at: value.location)
        }
        .onEnded { value in
            customizer.endDrag(at: value.location)
            previewLocation = nil
        }
    }
}

struct MediaToolbarCustomizeChrome: View {
    @ObservedObject private var customizer = MediaToolbarCustomizer.shared
    var editDrag: MediaToolbarEditDragModifier

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
                .background(paletteBoundsReader)
                .modifier(editDrag)

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
            .allowsHitTesting(!customizer.isDragging)
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
                    .background(paletteItemFrameReader(item))
            }
        }
    }

    private func paletteOpacity(for item: MediaToolbarItem) -> Double {
        if item.isSpace { return 1 }
        return customizer.slots.contains(where: { $0.item == item })
            ? 0.42 : 1
    }

    private var paletteBoundsReader: some View {
        GeometryReader { geo in
            Color.clear.preference(
                key: MediaToolbarEditGeometryKey.self,
                value: MediaToolbarEditGeometry(
                    paletteBounds: geo.frame(
                        in: .named(MediaToolbarCustomizer.editSpace)
                    )
                )
            )
        }
    }

    private func paletteItemFrameReader(_ item: MediaToolbarItem) -> some View {
        GeometryReader { geo in
            Color.clear.preference(
                key: MediaToolbarEditGeometryKey.self,
                value: MediaToolbarEditGeometry(
                    paletteItems: [
                        item: geo.frame(
                            in: .named(MediaToolbarCustomizer.editSpace)
                        )
                    ]
                )
            )
        }
    }
}

struct MediaToolbarCustomizeRow: View {
    @ObservedObject private var customizer = MediaToolbarCustomizer.shared

    var body: some View {
        HStack(spacing: 8) {
            ForEach(customizer.displaySlots) { slot in
                cell(slot)
            }
        }
        .animation(
            .interactiveSpring(response: 0.28, dampingFraction: 0.86),
            value: customizer.displaySlots.map(\.id)
        )
        .frame(maxWidth: .infinity, minHeight: 58)
        .background(toolbarBoundsReader)
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
                .background(slotFrameReader(slot.id))
        }
    }

    private var toolbarBoundsReader: some View {
        GeometryReader { geo in
            Color.clear.preference(
                key: MediaToolbarEditGeometryKey.self,
                value: MediaToolbarEditGeometry(
                    toolbarBounds: geo.frame(
                        in: .named(MediaToolbarCustomizer.editSpace)
                    )
                )
            )
        }
    }

    private func slotFrameReader(_ id: UUID) -> some View {
        GeometryReader { geo in
            Color.clear.preference(
                key: MediaToolbarEditGeometryKey.self,
                value: MediaToolbarEditGeometry(
                    slots: [
                        id: geo.frame(
                            in: .named(MediaToolbarCustomizer.editSpace)
                        )
                    ]
                )
            )
        }
    }
}

private struct MediaToolbarEditGeometryKey: PreferenceKey {
    static var defaultValue = MediaToolbarEditGeometry()

    static func reduce(
        value: inout MediaToolbarEditGeometry,
        nextValue: () -> MediaToolbarEditGeometry
    ) {
        let next = nextValue()
        value.slots.merge(next.slots, uniquingKeysWith: { _, n in n })
        value.paletteItems.merge(
            next.paletteItems,
            uniquingKeysWith: { _, n in n }
        )
        if next.toolbarBounds.width > 1 {
            value.toolbarBounds = next.toolbarBounds
        }
        if next.paletteBounds.width > 1 {
            value.paletteBounds = next.paletteBounds
        }
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
