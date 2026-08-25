//
//  LockAccessoriesLayoutMock.swift
//  Loffty
//
//  Created by Pierre-Louis ML on 25/08/2026.
//

import SwiftUI

struct LockAccessoriesLayoutMock: View {
    @ObservedObject private var settings = AppSettings.shared

    @State private var dragMode: DragMode = .idle
    @State private var dragTranslation: CGSize = .zero
    @State private var verticalDragStartTop: CGFloat?
    @State private var previewStripTop: CGFloat?
    @State private var chipFrames: [LockScreenAccessory: CGRect] = [:]

    private let mockHeight: CGFloat = 320
    private let stripHeight: CGFloat = 36
    private let clockBottom: CGFloat = 84
    private var cardTop: CGFloat {
        mockHeight - mockHeight * 0.19 - 56
    }

    private enum DragMode: Equatable {
        case idle
        case vertical
        case reorder(LockScreenAccessory)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(
                "Drag chips sideways to reorder. Drag the ≡ handle to move the row."
            )
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            GeometryReader { geo in
                let width = geo.size.width
                ZStack(alignment: .top) {
                    background
                    chrome
                    accessoryStrip
                        .frame(maxWidth: .infinity)
                        .padding(.top, displayedStripTop)
                }
                .frame(width: width, height: mockHeight)
                .coordinateSpace(name: "lockAccessoryMock")
                .clipShape(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(.white.opacity(0.08), lineWidth: 1)
                }
                .onPreferenceChange(LockAccessoryChipFrameKey.self) {
                    chipFrames = $0
                }
            }
            .frame(height: mockHeight)
        }
    }

    private var settingsStripTop: CGFloat {
        let fraction = LockAccessoriesMetrics.clampedTopInsetFraction(
            settings.lockScreenAccessoriesTopInsetFraction
        )
        return clampedStripTop(mockHeight * fraction)
    }

    private var displayedStripTop: CGFloat {
        previewStripTop ?? settingsStripTop
    }

    private func clampedStripTop(_ raw: CGFloat) -> CGFloat {
        let maxTop = max(clockBottom, cardTop - stripHeight - 12)
        return min(max(raw, clockBottom), maxTop)
    }

    private var background: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.22, green: 0.28, blue: 0.24),
                        Color(red: 0.12, green: 0.14, blue: 0.13),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
    }

    private var chrome: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(.black.opacity(0.85))
                .frame(width: 48, height: 9)
                .padding(.top, 7)

            Text(Self.sampleDate)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .padding(.top, 8)

            Text("9:41")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.top, 1)

            Spacer(minLength: 0)

            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.white.opacity(0.14))
                .frame(width: 150, height: 54)
                .overlay {
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(.white.opacity(0.28))
                            .frame(width: 28, height: 28)
                        VStack(alignment: .leading, spacing: 3) {
                            Capsule()
                                .fill(.white.opacity(0.55))
                                .frame(width: 64, height: 5)
                            Capsule()
                                .fill(.white.opacity(0.28))
                                .frame(width: 44, height: 4)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                }
                .padding(.bottom, mockHeight * 0.19)

            Circle()
                .fill(.white.opacity(0.22))
                .frame(width: 18, height: 18)
                .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }

    private var accessoryStrip: some View {
        HStack(spacing: 10) {
            verticalHandle

            ForEach(settings.lockScreenAccessoryOrder) { accessory in
                chip(accessory)
                    .opacity(chipOpacity(accessory))
                    .offset(chipOffset(accessory))
                    .zIndex(dragMode == .reorder(accessory) ? 10 : 0)
                    .background(chipFrameReader(accessory))
                    .highPriorityGesture(chipGesture(for: accessory))
            }
        }
        .padding(.horizontal, 4)
        .transaction { transaction in
            if dragMode != .idle {
                transaction.animation = nil
            }
        }
    }

    private var verticalHandle: some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white.opacity(0.55))
            .frame(width: 22, height: 28)
            .background(
                Capsule(style: .continuous)
                    .fill(.white.opacity(0.12))
            )
            .contentShape(Capsule())
            .help("Drag to move the row")
            .highPriorityGesture(handleGesture)
            .opacity(dragMode == .vertical ? 0.85 : 1)
    }

    private var handleGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if dragMode == .idle {
                    dragMode = .vertical
                    verticalDragStartTop = displayedStripTop
                }
                guard dragMode == .vertical,
                    let start = verticalDragStartTop
                else { return }
                previewStripTop = clampedStripTop(
                    start + value.translation.height
                )
            }
            .onEnded { _ in
                commitVerticalPreview()
                endDrag()
            }
    }

    private func chip(_ accessory: LockScreenAccessory) -> some View {
        HStack(spacing: 4) {
            Image(systemName: accessory.mockSymbol)
                .font(.system(size: 12, weight: .semibold))
            Text(accessory.mockLabel)
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .help(accessory.title)
    }

    private func chipOpacity(_ accessory: LockScreenAccessory) -> Double {
        if dragMode == .reorder(accessory) { return 0.9 }
        return settings.isLockScreenAccessoryEnabled(accessory) ? 1 : 0.38
    }

    private func chipOffset(_ accessory: LockScreenAccessory) -> CGSize {
        guard dragMode == .reorder(accessory) else { return .zero }
        return dragTranslation
    }

    private func chipFrameReader(_ accessory: LockScreenAccessory) -> some View
    {
        GeometryReader { geo in
            Color.clear.preference(
                key: LockAccessoryChipFrameKey.self,
                value: [
                    accessory: geo.frame(in: .named("lockAccessoryMock"))
                ]
            )
        }
    }

    private func chipGesture(for accessory: LockScreenAccessory) -> some Gesture
    {
        DragGesture(
            minimumDistance: 4,
            coordinateSpace: .named("lockAccessoryMock")
        )
        .onChanged { value in
            if dragMode == .idle {
                dragMode = .reorder(accessory)
            }
            guard dragMode == .reorder(accessory) else { return }
            dragTranslation = value.translation
            reorderIfNeeded(dragging: accessory, fingerX: value.location.x)
        }
        .onEnded { _ in
            endDrag()
        }
    }

    private func commitVerticalPreview() {
        guard let preview = previewStripTop else { return }
        let fraction = preview / mockHeight
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            settings.lockScreenAccessoriesTopInsetFraction =
                LockAccessoriesMetrics.clampedTopInsetFraction(fraction)
        }
    }

    private func reorderIfNeeded(
        dragging: LockScreenAccessory,
        fingerX: CGFloat
    ) {
        let ordered = settings.lockScreenAccessoryOrder
        guard ordered.firstIndex(of: dragging) != nil else { return }

        let centers: [(LockScreenAccessory, CGFloat)] = ordered.compactMap {
            accessory in
            guard let frame = chipFrames[accessory] else { return nil }
            return (accessory, frame.midX)
        }
        guard !centers.isEmpty else { return }

        let target =
            centers.min(by: { abs($0.1 - fingerX) < abs($1.1 - fingerX) })?
            .0
        guard let target,
            let to = ordered.firstIndex(of: target),
            ordered.firstIndex(of: dragging) != to
        else { return }

        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            settings.moveLockScreenAccessory(dragging, to: to)
        }
    }

    private func endDrag() {
        dragMode = .idle
        dragTranslation = .zero
        verticalDragStartTop = nil
        previewStripTop = nil
    }

    private static var sampleDate: String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("EEE d MMM")
        return formatter.string(from: Date())
    }
}

private struct LockAccessoryChipFrameKey: PreferenceKey {
    static var defaultValue: [LockScreenAccessory: CGRect] = [:]

    static func reduce(
        value: inout [LockScreenAccessory: CGRect],
        nextValue: () -> [LockScreenAccessory: CGRect]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

extension LockScreenAccessory {
    fileprivate var mockSymbol: String {
        switch self {
        case .weather: "cloud.sun.fill"
        case .bluetooth: "airpodspro"
        case .battery: "battery.100"
        }
    }

    fileprivate var mockLabel: String {
        switch self {
        case .weather: "25°"
        case .bluetooth: "AirPods"
        case .battery: "80%"
        }
    }
}
