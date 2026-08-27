//
//  WeatherContents.swift
//  Loffty
//
//  Created by Pierre-Louis ML on 23/08/2026.
//

import SwiftUI

struct WeatherNotchContent: View {
    @EnvironmentObject private var vm: NotchViewModel
    @ObservedObject private var weather = WeatherController.shared
    @ObservedObject private var settings = AppSettings.shared
    let m: NotchMetrics

    private var metricTemp: Bool {
        WeatherFormatting.usesMetricTemperature(settings.weatherTemperatureUnit)
    }
    private var metricWind: Bool {
        WeatherFormatting.usesMetricWind(settings.weatherWindUnit)
    }

    var body: some View {
        ZStack {
            if let snap = weather.snapshot, weather.status == .ready {
                slideContent(snap)
                    .id(vm.weatherSlide)
                    .offset(y: vm.weatherSlideOffset)
                    .scaleEffect(
                        x: 1 + abs(vm.weatherSlideOffset) / 5000,
                        y: 1 + abs(vm.weatherSlideOffset) / 10000,
                        anchor: .center
                    )
                    .transition(slideTransition)
            } else {
                placeholderHeader
                    .padding(.horizontal, 44)
                    .transition(.opacity)
            }
        }
        .frame(width: m.width, height: m.height)
        .clipped()
        .onAppear { weather.prepare() }
    }

    @ViewBuilder
    private func slideContent(_ snap: WeatherSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: m.notchH)
            Spacer(minLength: 0)
            Group {
                switch activeSection {
                case .overview:
                    overview(snap)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .charts:
                    VStack(alignment: .leading, spacing: 8) {
                        slideTitle("Forecast trends", subtitle: "Next 24 hours")
                        if snap.hours.count >= 3 {
                            WeatherSparklineCard(
                                title: "Temperature",
                                values: snap.hours.map(\.temperatureC),
                                labels: hourGraphLabels(snap.hours),
                                metric: metricTemp
                            )
                        }
                        if settings.weatherShowPrecip, snap.hours.count >= 3 {
                            WeatherPrecipCard(hours: snap.hours)
                        }
                    }
                case .forecast:
                    VStack(alignment: .leading, spacing: 8) {
                        slideTitle(
                            "Daily forecast",
                            subtitle: "Next several days"
                        )
                        if snap.days.count >= 2 { days(snap) }
                    }
                }
            }
            .frame(
                height: max(1, m.height - m.notchH - 12),
                alignment: .center
            )
            .frame(maxWidth: .infinity)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 36)
        .padding(.bottom, 12)
        .frame(width: m.width, height: m.height, alignment: .topLeading)
    }

    private var activeSection: WeatherSection {
        settings.weatherSectionOrder.indices.contains(vm.weatherSlide.rawValue)
            ? settings.weatherSectionOrder[vm.weatherSlide.rawValue]
            : .overview
    }

    private var slideTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.985)),
            removal: .opacity.combined(with: .scale(scale: 1.015))
        )
    }

    private var slideIndicator: some View {
        VStack(spacing: 5) {
            ForEach(WeatherSlide.allCases, id: \.rawValue) { slide in
                Capsule()
                    .fill(.white.opacity(slide == vm.weatherSlide ? 0.75 : 0.2))
                    .frame(width: 3, height: slide == vm.weatherSlide ? 14 : 5)
                    .animation(.easeOut(duration: 0.2), value: vm.weatherSlide)
            }
        }
    }

    private func slideTitle(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.92))
            Text(subtitle)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.34))
        }
    }

    @ViewBuilder
    private var header: some View {
        if let snap = weather.snapshot,
            weather.status == .ready
                || weather.status == .locating
        {
            currentPane(snap)
        } else {
            placeholderHeader
        }
    }

    private func overview(_ snap: WeatherSnapshot) -> some View {
        HStack(alignment: .top, spacing: 18) {
            currentPane(snap)
            if settings.weatherShowHourly {
                hourlyPane(snap)
                    .frame(width: 132)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(.white.opacity(0.14))
                            .frame(width: 1)
                            .padding(.vertical, 2)
                            .offset(x: -9)
                    }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func currentPane(_ snap: WeatherSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if settings.weatherShowLocation {
                Text(snap.locality)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.38))
                    .lineLimit(1)
                    .padding(.bottom, 1)
            }
            HStack(alignment: .center, spacing: 7) {
                Text(
                    WeatherFormatting.temperatureLabel(
                        snap.temperatureC,
                        metric: metricTemp
                    )
                )
                .font(.system(size: 48, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.white)
                .tracking(-1.6)
                .minimumScaleFactor(0.62)
                .lineLimit(1)
                Image(
                    systemName: WeatherSymbol.systemName(
                        code: snap.weatherCode,
                        isDay: snap.isDay
                    )
                )
                .font(.system(size: 24, weight: .regular))
                .symbolRenderingMode(.multicolor)
            }
            if settings.weatherShowHighLow || settings.weatherShowUV {
                HStack(spacing: 6) {
                    if settings.weatherShowHighLow {
                        Text(
                            WeatherFormatting.highLowLabel(
                                highC: snap.highC,
                                lowC: snap.lowC,
                                metric: metricTemp
                            )
                        )
                    }
                    if settings.weatherShowUV {
                        Text(WeatherFormatting.uvLabel(snap.uvIndex))
                    }
                }
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.48))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .padding(.top, 2)
            }
            if settings.weatherShowWind {
                HStack(spacing: 4) {
                    Image(systemName: "wind")
                        .font(.system(size: 9, weight: .semibold))
                    Text(
                        WeatherFormatting.windLabel(
                            snap.windKmh,
                            metric: metricWind
                        )
                    )
                    .monospacedDigit()
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.42))
                .padding(.top, 3)
            }
            if snap.hours.count >= 3 {
                Spacer(minLength: 8)
                WeatherCurrentTrend(
                    hours: Array(snap.hours.prefix(10)),
                    now: Date()
                )
                .frame(height: 26)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var placeholderHeader: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(placeholderTitle)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.42))
                Text(placeholderDetail)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
                if showsPermissionAction {
                    Text(
                        weather.status == .denied
                            ? "Opens System Settings"
                            : "Opens a system prompt"
                    )
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.32))
                }
            }
            Spacer(minLength: 0)
            Image(systemName: placeholderSymbol)
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(.white.opacity(0.28))
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { handlePlaceholderTap() }
    }

    private func handlePlaceholderTap() {
        switch weather.status {
        case .denied:
            PrivacyAccess.openLocationSettings()
        case .needsPermission, .idle, .locating, .failed:
            weather.requestAccessFromUser()
        case .ready:
            break
        }
    }

    private var showsPermissionAction: Bool {
        switch weather.status {
        case .needsPermission, .denied, .failed: true
        default: false
        }
    }

    private var placeholderTitle: String {
        switch weather.status {
        case .denied: "Location Off"
        case .failed: "Unavailable"
        case .needsPermission, .idle: "Weather"
        case .locating: "Locating"
        case .ready: "Weather"
        }
    }

    private var placeholderDetail: String {
        switch weather.status {
        case .denied: "Turn on Location in System Settings."
        case .failed: "Couldn't load local conditions."
        case .needsPermission, .idle: "Allow Location for a local forecast."
        case .locating: "Finding your local conditions…"
        case .ready: ""
        }
    }

    private var placeholderSymbol: String {
        switch weather.status {
        case .denied: "location.slash"
        case .failed: "icloud.slash"
        case .locating: "location"
        default: "location.fill"
        }
    }

    private func hourlyPane(_ snap: WeatherSnapshot) -> some View {
        let count = 4
        let items = WeatherHourList.upcoming(snap.hours, limit: count)
        return VStack(spacing: 0) {
            if items.isEmpty {
                ForEach(0..<count, id: \.self) { index in
                    if index > 0 { Spacer(minLength: 10) }
                    hourRowPlaceholder
                }
            } else {
                ForEach(Array(items.enumerated()), id: \.offset) {
                    index,
                    hour in
                    if index > 0 { Spacer(minLength: 10) }
                    hourRow(hour)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func hourRow(_ hour: WeatherHour) -> some View {
        HStack(spacing: 0) {
            Text(WeatherFormatting.hourLabel(hour.date))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.46))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(width: 48, alignment: .leading)
            Image(
                systemName: WeatherSymbol.systemName(
                    code: hour.weatherCode,
                    isDay: WeatherSymbol.isDay(at: hour.date)
                )
            )
            .font(.system(size: 14, weight: .regular))
            .symbolRenderingMode(.multicolor)
            .frame(maxWidth: .infinity)
            Text(
                WeatherFormatting.temperatureLabel(
                    hour.temperatureC,
                    metric: metricTemp
                )
            )
            .font(.system(size: 12, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(.white.opacity(0.92))
            .frame(width: 32, alignment: .trailing)
        }
    }

    private var hourRowPlaceholder: some View {
        HStack(spacing: 0) {
            Capsule().fill(.white.opacity(0.07)).frame(width: 26, height: 5)
            Spacer(minLength: 2)
            Circle().fill(.white.opacity(0.07)).frame(width: 11, height: 11)
            Spacer(minLength: 2)
            Capsule().fill(.white.opacity(0.07)).frame(width: 16, height: 6)
        }
    }

    private func days(_ snap: WeatherSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Next days")
            VStack(spacing: 6) {
                ForEach(Array(snap.days.prefix(4).enumerated()), id: \.offset) {
                    _,
                    day in
                    HStack(spacing: 10) {
                        Text(WeatherFormatting.weekdayLabel(day.date))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                            .frame(width: 34, alignment: .leading)
                        Image(
                            systemName: WeatherSymbol.systemName(
                                code: day.weatherCode,
                                isDay: true
                            )
                        )
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(width: 16)
                        Text(
                            WeatherFormatting.temperatureLabel(
                                day.lowC,
                                metric: metricTemp
                            )
                        )
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.38))
                        .monospacedDigit()
                        WeatherDayRangeBar()
                            .frame(height: 4)
                        Text(
                            WeatherFormatting.temperatureLabel(
                                day.highC,
                                metric: metricTemp
                            )
                        )
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.82))
                        .monospacedDigit()
                    }
                }
            }
        }
    }

    private func hourGraphLabels(_ hours: [WeatherHour]) -> (String, String) {
        guard let first = hours.first, let last = hours.last else {
            return ("", "")
        }
        return (
            WeatherFormatting.hourLabel(first.date),
            WeatherFormatting.hourLabel(last.date)
        )
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.white.opacity(0.32))
            .textCase(.uppercase)
            .tracking(0.4)
    }
}

private struct WeatherCurrentTrend: View {
    var hours: [WeatherHour]
    var now: Date

    private let line = Color(red: 0.58, green: 0.82, blue: 0.98)

    var body: some View {
        let values = hours.map(\.temperatureC)
        let points = WeatherGraph.normalized(values)
        let current = WeatherGraph.currentIndex(in: hours, now: now)
        Canvas { context, size in
            guard points.count > 1 else { return }
            let inset: CGFloat = 3
            let plot = CGSize(
                width: max(1, size.width - inset * 2),
                height: max(1, size.height * 0.62)
            )
            func point(at index: Int) -> CGPoint {
                let x =
                    inset
                    + plot.width * CGFloat(index)
                    / CGFloat(points.count - 1)
                let y = 3 + (plot.height - points[index] * plot.height)
                return CGPoint(x: x, y: y)
            }
            let anchors = points.indices.map(point(at:))
            let sampled = interpolate(anchors, steps: 12)
            let currentPoint = point(at: min(current, anchors.count - 1))
            let past = sampled.filter { $0.x <= currentPoint.x + 0.5 }
            let future = sampled.filter { $0.x >= currentPoint.x - 0.5 }

            var baseline = Path()
            baseline.move(to: CGPoint(x: inset, y: currentPoint.y))
            baseline.addLine(
                to: CGPoint(x: size.width - inset, y: currentPoint.y)
            )
            context.stroke(
                baseline,
                with: .color(.white.opacity(0.14)),
                style: StrokeStyle(lineWidth: 0.6, dash: [1.5, 2.6])
            )

            if future.count > 1, let first = future.first,
                let last = future.last
            {
                var glow = Path()
                glow.move(to: first)
                for sample in future.dropFirst() { glow.addLine(to: sample) }
                var fill = glow
                fill.addLine(to: CGPoint(x: last.x, y: size.height))
                fill.addLine(to: CGPoint(x: first.x, y: size.height))
                fill.closeSubpath()
                let peak = future.map(\.y).min() ?? first.y
                context.fill(
                    fill,
                    with: .linearGradient(
                        Gradient(stops: [
                            .init(color: line.opacity(0.34), location: 0),
                            .init(color: line.opacity(0.12), location: 0.42),
                            .init(color: line.opacity(0), location: 1),
                        ]),
                        startPoint: CGPoint(x: 0, y: peak),
                        endPoint: CGPoint(x: 0, y: size.height)
                    )
                )
                context.stroke(
                    glow,
                    with: .color(line.opacity(0.22)),
                    style: StrokeStyle(
                        lineWidth: 4,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
                context.stroke(
                    glow,
                    with: .color(line.opacity(0.95)),
                    style: StrokeStyle(
                        lineWidth: 1.6,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
            }

            if past.count > 1 {
                var history = Path()
                if let first = past.first {
                    history.move(to: first)
                    for sample in past.dropFirst() {
                        history.addLine(to: sample)
                    }
                }
                context.stroke(
                    history,
                    with: .color(line.opacity(0.55)),
                    style: StrokeStyle(
                        lineWidth: 1.35,
                        lineCap: .round,
                        lineJoin: .round,
                        dash: [2.4, 2.8]
                    )
                )
            }

            let halo = Path(
                ellipseIn: CGRect(
                    x: currentPoint.x - 4.4,
                    y: currentPoint.y - 4.4,
                    width: 8.8,
                    height: 8.8
                )
            )
            context.fill(halo, with: .color(.white.opacity(0.2)))
            let dot = Path(
                ellipseIn: CGRect(
                    x: currentPoint.x - 2.4,
                    y: currentPoint.y - 2.4,
                    width: 4.8,
                    height: 4.8
                )
            )
            context.fill(dot, with: .color(.white))
        }
        .accessibilityHidden(true)
    }

    private func interpolate(_ points: [CGPoint], steps: Int) -> [CGPoint] {
        guard points.count > 1 else { return points }
        if points.count == 2 { return points }
        var samples: [CGPoint] = []
        samples.reserveCapacity((points.count - 1) * steps + 1)
        for index in 0..<(points.count - 1) {
            let p0 = index > 0 ? points[index - 1] : points[index]
            let p1 = points[index]
            let p2 = points[index + 1]
            let p3 = index + 2 < points.count ? points[index + 2] : p2
            for step in 0..<steps {
                let t = CGFloat(step) / CGFloat(steps)
                samples.append(catmull(p0, p1, p2, p3, t))
            }
        }
        if let last = points.last { samples.append(last) }
        return samples
    }

    private func catmull(
        _ p0: CGPoint,
        _ p1: CGPoint,
        _ p2: CGPoint,
        _ p3: CGPoint,
        _ t: CGFloat
    ) -> CGPoint {
        let t2 = t * t
        let t3 = t2 * t
        func sample(_ a: CGFloat, _ b: CGFloat, _ c: CGFloat, _ d: CGFloat)
            -> CGFloat
        {
            0.5
                * ((2 * b) + (-a + c) * t + (2 * a - 5 * b + 4 * c - d) * t2
                    + (-a + 3 * b - 3 * c + d) * t3)
        }
        return CGPoint(
            x: sample(p0.x, p1.x, p2.x, p3.x),
            y: sample(p0.y, p1.y, p2.y, p3.y)
        )
    }
}

private struct WeatherSparklineCard: View {
    var title: String
    var values: [Double]
    var labels: (String, String)
    var metric: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.32))
                    .textCase(.uppercase)
                    .tracking(0.4)
                Spacer(minLength: 0)
                if let min = values.min(), let max = values.max() {
                    Text(
                        "\(WeatherFormatting.temperatureLabel(min, metric: metric))–\(WeatherFormatting.temperatureLabel(max, metric: metric))"
                    )
                    .font(.system(size: 10, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.28))
                }
            }
            WeatherSparkline(values: values)
                .frame(height: 32)
            HStack {
                Text(labels.0)
                Spacer()
                Text(labels.1)
            }
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(.white.opacity(0.28))
        }
    }
}

private struct WeatherPrecipCard: View {
    var hours: [WeatherHour]

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Precipitation")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.32))
                .textCase(.uppercase)
                .tracking(0.4)
            WeatherPrecipBars(values: hours.map(\.precipMm))
                .frame(height: 26)
        }
    }
}

private struct WeatherSparkline: View {
    var values: [Double]

    var body: some View {
        let points = WeatherGraph.normalized(values)
        Canvas { context, size in
            guard points.count > 1 else { return }
            var line = Path()
            var fill = Path()
            for (index, y) in points.enumerated() {
                let x =
                    size.width * CGFloat(index) / CGFloat(points.count - 1)
                let py = size.height - (4 + y * (size.height - 8))
                let point = CGPoint(x: x, y: py)
                if index == 0 {
                    line.move(to: point)
                    fill.move(to: CGPoint(x: x, y: size.height))
                    fill.addLine(to: point)
                } else {
                    line.addLine(to: point)
                    fill.addLine(to: point)
                }
            }
            fill.addLine(to: CGPoint(x: size.width, y: size.height))
            fill.closeSubpath()
            context.fill(fill, with: .color(.white.opacity(0.08)))
            context.stroke(
                line,
                with: .color(.white.opacity(0.72)),
                style: StrokeStyle(
                    lineWidth: 1.4,
                    lineCap: .round,
                    lineJoin: .round
                )
            )
        }
    }
}

private struct WeatherPrecipBars: View {
    var values: [Double]

    var body: some View {
        let peak = max(values.max() ?? 0, 0.2)
        GeometryReader { geo in
            let count = max(values.count, 1)
            let gap: CGFloat = 1.5
            let width = max(
                1.5,
                (geo.size.width - gap * CGFloat(count - 1)) / CGFloat(count)
            )
            HStack(alignment: .bottom, spacing: gap) {
                ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                    RoundedRectangle(cornerRadius: 1.2, style: .continuous)
                        .fill(.white.opacity(value <= 0.05 ? 0.1 : 0.45))
                        .frame(
                            width: width,
                            height: max(
                                3,
                                geo.size.height * CGFloat(value / peak)
                            )
                        )
                }
            }
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: .bottom
            )
        }
    }
}

private struct WeatherDayRangeBar: View {
    var body: some View {
        GeometryReader { geo in
            Capsule()
                .fill(.white.opacity(0.1))
            Capsule()
                .fill(.white.opacity(0.45))
                .frame(width: max(10, geo.size.width * 0.55))
                .position(x: geo.size.width * 0.5, y: geo.size.height * 0.5)
        }
        .frame(maxWidth: .infinity)
    }
}
