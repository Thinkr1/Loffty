//
//  AirDropDropView.swift
//  Loffty
//
//  Created by Pierre-Louis ML on 16/07/2026.
//

import AppKit

enum AirDropDragProbe {
    static var isFileDragActive: Bool {
        let pb = NSPasteboard(
            name: NSPasteboard.Name("Apple CFPasteboard drag")
        )
        if pb.availableType(from: [.fileURL]) != nil { return true }
        let filenames = NSPasteboard.PasteboardType("NSFilenamesPboardType")
        return pb.availableType(from: [filenames]) != nil
    }
}

final class AirDropCatchView: NSView {
    var onDragEnter: (([URL]) -> Void)?
    var onDropURLs: (([URL]) -> Void)?
    var onDragExit: (() -> Void)?
    var isEnabled: (() -> Bool)?

    private var dragActive = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([
            .fileURL,
            NSPasteboard.PasteboardType("public.file-url"),
            NSPasteboard.PasteboardType("NSFilenamesPboardType"),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard isEnabled?() ?? false else { return nil }
        if dragActive || AirDropDragProbe.isFileDragActive { return self }
        return nil
    }

    override func draggingEntered(_ sender: any NSDraggingInfo)
        -> NSDragOperation
    {
        guard isEnabled?() ?? false else { return [] }
        let urls = extractURLs(from: sender)
        guard !urls.isEmpty else { return [] }
        dragActive = true
        onDragEnter?(urls)
        return .copy
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo)
        -> NSDragOperation
    {
        guard isEnabled?() ?? false else { return [] }
        return extractURLs(from: sender).isEmpty ? [] : .copy
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        dragActive = false
        onDragExit?()
    }

    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool
    {
        (isEnabled?() ?? false) && !extractURLs(from: sender).isEmpty
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let urls = extractURLs(from: sender)
        dragActive = false
        guard !urls.isEmpty else { return false }
        onDropURLs?(urls)
        return true
    }

    override func concludeDragOperation(_ sender: (any NSDraggingInfo)?) {
        dragActive = false
    }

    private func extractURLs(from info: NSDraggingInfo) -> [URL] {
        let pb = info.draggingPasteboard
        var urls: [URL] = []

        if let items = pb.readObjects(
            forClasses: [NSURL.self],
            options: [
                .urlReadingFileURLsOnly: true,
                .urlReadingContentsConformToTypes: ["public.item"],
            ]
        ) as? [URL] {
            urls.append(contentsOf: items)
        }

        if urls.isEmpty,
            let paths = pb.propertyList(
                forType: NSPasteboard.PasteboardType("NSFilenamesPboardType")
            ) as? [String]
        {
            urls.append(contentsOf: paths.map { URL(fileURLWithPath: $0) })
        }

        if urls.isEmpty,
            let strs = pb.propertyList(forType: .fileURL) as? [String]
        {
            urls.append(
                contentsOf: strs.compactMap {
                    URL(string: $0) ?? URL(fileURLWithPath: $0)
                }
            )
        }

        return urls.filter(\.isFileURL)
    }
}
