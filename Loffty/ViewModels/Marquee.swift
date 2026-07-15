//
//  Marquee.swift
//  Loffty
//
//  Created by Pierre-Louis ML on 15/07/2026.
//

import SwiftUI

private struct MarqueeWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct MarqueeText: View {
    let text: String
    let font: Font
    let color: Color
    let height: CGFloat
    var speed: CGFloat = 26
    var gap: CGFloat = 32

    @State private var textWidth: CGFloat = 0
    @State private var paused = false

    var body: some View {
        GeometryReader { geo in
            let overflows = textWidth > geo.size.width + 1

            Group {
                if overflows {
                    TimelineView(
                        .animation(minimumInterval: 1.0 / 60.0, paused: paused)
                    ) { ctx in
                        let loop = textWidth + gap
                        let t = ctx.date.timeIntervalSinceReferenceDate
                        let x =
                            loop > 0
                            ? -CGFloat(
                                t.truncatingRemainder(
                                    dividingBy: Double(loop / speed)
                                )
                                    * Double(speed)
                            )
                            : 0

                        HStack(spacing: gap) {
                            label
                            label
                        }
                        .offset(x: x)
                    }
                } else {
                    label
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentTransition(.numericText())
                        .animation(.smooth(duration: 0.18), value: text)
                }
            }
            .frame(width: geo.size.width, alignment: .leading)
            .clipped()
            .onHover { paused = overflows && $0 }
        }
        .frame(height: height)
        .onPreferenceChange(MarqueeWidthKey.self) { textWidth = $0 }
        .onChange(of: text) { _, _ in textWidth = 0 }
    }

    private var label: some View {
        Text(text)
            .font(font)
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: MarqueeWidthKey.self,
                        value: proxy.size.width
                    )
                }
            }
    }
}
