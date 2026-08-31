//
//  MediaToolbar.swift
//  Loffty
//
//  Created by Pierre-Louis ML on 20/08/2026.
//

import Combine
import CoreGraphics
import CoreTransferable
import Foundation
import UniformTypeIdentifiers

nonisolated enum MediaToolbarItem: String, CaseIterable, Identifiable, Codable,
    Sendable
{
    case like
    case skipBack
    case previous
    case playPause
    case next
    case skipForward
    case goLive
    case space

    var id: String { rawValue }

    var isSpace: Bool { self == .space }

    var title: String {
        switch self {
        case .like: "Favourite"
        case .skipBack: "Back 10 Seconds"
        case .previous: "Previous"
        case .playPause: "Play"
        case .next: "Next"
        case .skipForward: "Forward 10 Seconds"
        case .goLive: "Go to Live"
        case .space: "Flexible Space"
        }
    }

    var symbol: String {
        switch self {
        case .like: "heart"
        case .skipBack: "gobackward.10"
        case .previous: "backward.fill"
        case .playPause: "play.fill"
        case .next: "forward.fill"
        case .skipForward: "goforward.10"
        case .goLive: "dot.radiowaves.left.and.right"
        case .space: "arrow.left.and.right"
        }
    }

    var controlSize: CGFloat {
        switch self {
        case .playPause: 26
        case .previous, .next: 20
        default: 18
        }
    }

    static let palette: [MediaToolbarItem] = [
        .like, .skipBack, .previous, .playPause, .next, .skipForward, .goLive,
        .space,
    ]

    static func defaultLayout(includeLike: Bool = true) -> [MediaToolbarItem] {
        var items: [MediaToolbarItem] = includeLike ? [.like] : []
        items += [
            .skipBack, .space, .previous, .playPause, .next, .space,
            .skipForward,
        ]
        return items
    }

    static func sanitize(_ items: [MediaToolbarItem]) -> [MediaToolbarItem] {
        var seen = Set<MediaToolbarItem>()
        var result: [MediaToolbarItem] = []
        for item in items {
            if item.isSpace {
                result.append(item)
                continue
            }
            guard seen.insert(item).inserted else { continue }
            result.append(item)
        }
        if result.allSatisfy(\.isSpace) {
            return defaultLayout()
        }
        return result
    }

    static func decode(_ raw: [String]?) -> [MediaToolbarItem]? {
        guard let raw else { return nil }
        let parsed = raw.compactMap(MediaToolbarItem.init(rawValue:))
        guard !parsed.isEmpty else { return nil }
        return sanitize(parsed)
    }

    static func placing(
        _ items: [MediaToolbarItem],
        item: MediaToolbarItem,
        from sourceIndex: Int?,
        at destination: Int
    ) -> [MediaToolbarItem] {
        var next = items
        if let sourceIndex, next.indices.contains(sourceIndex) {
            let moved = next.remove(at: sourceIndex)
            let dest =
                destination > sourceIndex ? destination - 1 : destination
            next.insert(moved, at: min(max(dest, 0), next.count))
            return sanitize(next)
        }
        if !item.isSpace, let existing = next.firstIndex(of: item) {
            return placing(
                next,
                item: item,
                from: existing,
                at: destination
            )
        }
        next.insert(item, at: min(max(destination, 0), next.count))
        return sanitize(next)
    }

    static func removing(_ items: [MediaToolbarItem], at index: Int)
        -> [MediaToolbarItem]
    {
        guard items.indices.contains(index) else { return items }
        var next = items
        next.remove(at: index)
        return sanitize(next)
    }
}

nonisolated struct MediaToolbarPayload: Codable, Transferable, Sendable {
    var raw: String
    var index: Int?

    var item: MediaToolbarItem? { MediaToolbarItem(rawValue: raw) }

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .json)
    }
}

struct MediaToolbarSlot: Identifiable, Equatable {
    let id: UUID
    var item: MediaToolbarItem

    init(id: UUID = UUID(), item: MediaToolbarItem) {
        self.id = id
        self.item = item
    }
}

struct MediaToolbarEditGeometry: Equatable {
    var slots: [UUID: CGRect] = [:]
    var paletteItems: [MediaToolbarItem: CGRect] = [:]
    var toolbarBounds: CGRect = .null
    var paletteBounds: CGRect = .null
}

enum MediaToolbarDragHit: Equatable {
    case toolbar(UUID)
    case palette(MediaToolbarItem)
}

enum MediaToolbarDragZone: Equatable {
    case toolbar
    case palette
    case outside
}

enum MediaToolbarCustomizeLayout {
    static let width: CGFloat = 540
    static let paletteHeight: CGFloat = 260
    static let playingHeight: CGFloat = 196
    static let playingHeightWithAlbum: CGFloat = 206

    static func expandedHeight(showAlbum: Bool) -> CGFloat {
        (showAlbum ? playingHeightWithAlbum : playingHeight) + paletteHeight
    }
}

@MainActor
final class MediaToolbarCustomizer: ObservableObject {
    static let shared = MediaToolbarCustomizer()
    static let placeholderID = UUID()
    static let editSpace = "mediaToolbarEdit"

    @Published private(set) var isCustomizing = false
    @Published private(set) var slots: [MediaToolbarSlot] = []
    @Published private(set) var insertionIndex: Int?
    @Published private(set) var isOverPalette = false
    @Published private(set) var isOverToolbar = false
    @Published private(set) var isDragging = false
    @Published private(set) var dragSource: DragSource?

    enum DragSource {
        case toolbar
        case palette
    }

    private(set) var reopenSettings = false
    private var drag: MediaToolbarSlot?
    private var didDrop = false
    var editGeometry = MediaToolbarEditGeometry()

    var draggingItem: MediaToolbarItem? { drag?.item }

    var displaySlots: [MediaToolbarSlot] {
        guard isCustomizing else { return slots }
        var next = slots
        if let drag {
            next.removeAll { $0.id == drag.id }
            if !isOverPalette, let insertionIndex {
                let index = min(max(insertionIndex, 0), next.count)
                next.insert(
                    MediaToolbarSlot(id: Self.placeholderID, item: drag.item),
                    at: index
                )
            }
        }
        return next
    }

    func begin(reopenSettings: Bool) {
        self.reopenSettings = reopenSettings
        slots = AppSettings.shared.mediaToolbarItems.map {
            MediaToolbarSlot(item: $0)
        }
        clearDrag()
        editGeometry = MediaToolbarEditGeometry()
        isCustomizing = true
    }

    func end() {
        persist()
        clearDrag()
        isCustomizing = false
        if reopenSettings {
            reopenSettings = false
            SettingsOpener.shared.open()
        }
    }

    func restoreDefaults() {
        slots = MediaToolbarItem.defaultLayout().map {
            MediaToolbarSlot(item: $0)
        }
        persist()
    }

    func beginDrag(at point: CGPoint, geometry: MediaToolbarEditGeometry? = nil)
    {
        let geometry = geometry ?? editGeometry
        guard !isDragging else { return }
        switch Self.hitTarget(at: point, geometry: geometry) {
        case .toolbar(let id):
            guard let index = slots.firstIndex(where: { $0.id == id })
            else { return }
            beginToolbarDrag(slots[index], at: index)
        case .palette(let item):
            beginPaletteDrag(item)
        case nil:
            return
        }
    }

    func updateDrag(
        at point: CGPoint,
        geometry: MediaToolbarEditGeometry? = nil
    ) {
        let geometry = geometry ?? editGeometry
        guard isDragging else { return }
        switch Self.dragZone(
            point: point,
            toolbar: geometry.toolbarBounds,
            palette: geometry.paletteBounds
        ) {
        case .palette:
            hoverPalette()
        case .toolbar:
            let pairs = geometry.slots.map { (id: $0.key, frame: $0.value) }
            setInsertion(
                Self.insertionIndex(
                    x: point.x,
                    frames: pairs,
                    placeholder: Self.placeholderID,
                    current: insertionIndex
                )
            )
        case .outside:
            leaveDropZones()
        }
    }

    func endDrag(at point: CGPoint, geometry: MediaToolbarEditGeometry? = nil) {
        let geometry = geometry ?? editGeometry
        updateDrag(at: point, geometry: geometry)
        finishIfNeeded()
    }

    func beginToolbarDrag(_ slot: MediaToolbarSlot, at index: Int) {
        drag = slot
        dragSource = .toolbar
        isDragging = true
        didDrop = false
        isOverPalette = false
        isOverToolbar = true
        insertionIndex = index
    }

    func beginPaletteDrag(_ item: MediaToolbarItem) {
        if !item.isSpace, let existing = slots.first(where: { $0.item == item })
        {
            let index = slots.firstIndex(of: existing) ?? 0
            beginToolbarDrag(existing, at: index)
            return
        }
        drag = MediaToolbarSlot(item: item)
        dragSource = .palette
        isDragging = true
        didDrop = false
        isOverPalette = false
        isOverToolbar = false
        insertionIndex = nil
    }

    func setInsertion(_ index: Int) {
        isOverPalette = false
        isOverToolbar = true
        guard insertionIndex != index else { return }
        insertionIndex = index
    }

    func hoverPalette() {
        guard isDragging else { return }
        isOverPalette = true
        isOverToolbar = false
        insertionIndex = nil
    }

    func leaveToolbar() {
        guard isDragging else { return }
        isOverToolbar = false
    }

    func leaveDropZones() {
        guard isDragging else { return }
        isOverToolbar = false
        isOverPalette = false
        insertionIndex = nil
    }

    func commitToolbarDrop() {
        guard isDragging, let drag else { return }
        didDrop = true
        var next = slots.filter { $0.id != drag.id }
        let index = min(max(insertionIndex ?? next.count, 0), next.count)
        next.insert(drag, at: index)
        slots = Self.sanitizeSlots(next)
        persist()
        clearDrag()
    }

    func commitPaletteDrop() {
        guard isDragging else { return }
        didDrop = true
        if let drag {
            slots = Self.sanitizeSlots(slots.filter { $0.id != drag.id })
            persist()
        }
        clearDrag()
    }

    func finishIfNeeded() {
        guard isDragging, !didDrop else { return }
        switch Self.dragEndAction(
            source: dragSource,
            overToolbar: isOverToolbar,
            overPalette: isOverPalette
        ) {
        case .insert:
            commitToolbarDrop()
        case .remove:
            commitPaletteDrop()
        case .cancel:
            clearDrag()
        }
    }

    enum DragEndAction {
        case insert
        case remove
        case cancel
    }

    nonisolated static func dragEndAction(
        source: DragSource?,
        overToolbar: Bool,
        overPalette: Bool
    ) -> DragEndAction {
        if source == .toolbar, overPalette || !overToolbar {
            return .remove
        }
        if overToolbar {
            return .insert
        }
        return .cancel
    }

    private func persist() {
        AppSettings.shared.mediaToolbarItems = slots.map(\.item)
    }

    private func clearDrag() {
        drag = nil
        dragSource = nil
        isDragging = false
        isOverPalette = false
        isOverToolbar = false
        insertionIndex = nil
        didDrop = false
    }

    nonisolated static func hitTarget(
        at point: CGPoint,
        geometry: MediaToolbarEditGeometry
    ) -> MediaToolbarDragHit? {
        for (id, frame) in geometry.slots {
            if id == placeholderID { continue }
            if frame.insetBy(dx: -4, dy: -8).contains(point) {
                return .toolbar(id)
            }
        }
        for (item, frame) in geometry.paletteItems {
            if frame.insetBy(dx: -4, dy: -4).contains(point) {
                return .palette(item)
            }
        }
        return nil
    }

    nonisolated static func dragZone(
        point: CGPoint,
        toolbar: CGRect,
        palette: CGRect
    ) -> MediaToolbarDragZone {
        if !toolbar.isNull, toolbar.width > 1,
            toolbar.insetBy(dx: 0, dy: -12).contains(point)
        {
            return .toolbar
        }
        if !palette.isNull, palette.width > 1, palette.contains(point) {
            return .palette
        }
        return .outside
    }

    nonisolated static func insertionIndex(
        x: CGFloat,
        frames: [CGRect]
    ) -> Int {
        insertionIndex(
            x: x,
            frames: frames.enumerated().map {
                (id: UUID(), frame: $0.element)
            },
            placeholder: UUID(),
            current: nil
        )
    }

    nonisolated static func insertionIndex(
        x: CGFloat,
        frames: [(id: UUID, frame: CGRect)],
        placeholder: UUID,
        current: Int?
    ) -> Int {
        let sorted = frames.sorted { $0.frame.minX < $1.frame.minX }
        if let gap = sorted.first(where: { $0.id == placeholder })?.frame,
            x >= gap.minX, x <= gap.maxX
        {
            return current
                ?? sorted.firstIndex(where: { $0.id == placeholder }) ?? 0
        }
        let without = sorted.filter { $0.id != placeholder }
        for (i, item) in without.enumerated() {
            if x < item.frame.midX { return i }
        }
        return without.count
    }

    static func sanitizeSlots(_ slots: [MediaToolbarSlot]) -> [MediaToolbarSlot]
    {
        var seen = Set<MediaToolbarItem>()
        var result: [MediaToolbarSlot] = []
        for slot in slots {
            if slot.item.isSpace {
                result.append(slot)
                continue
            }
            guard seen.insert(slot.item).inserted else { continue }
            result.append(slot)
        }
        if result.allSatisfy({ $0.item.isSpace }) {
            return MediaToolbarItem.defaultLayout().map {
                MediaToolbarSlot(item: $0)
            }
        }
        return result
    }
}
