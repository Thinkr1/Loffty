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
                    VStack(alignment: .leading, spacing: 12) {
                        readyHeader(snap)
                        if settings.weatherShowHourly { hours(snap) }
                    }
                case .charts:
                    VStack(alignment: .leading, spacing: 12) {
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
                    VStack(alignment: .leading, spacing: 12) {
                        slideTitle(
                            "Daily forecast",
                            subtitle: "Next several days"
                        )
                        if snap.days.count >= 2 { days(snap) }
                    }
                }
            }
            .frame(
                height: max(1, m.height - m.notchH - 18),
                alignment: .center
            )
            .frame(maxWidth: .infinity)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 38)
        .padding(.bottom, 18)
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
            readyHeader(snap)
        } else {
            placeholderHeader
        }
    }

    private func readyHeader(_ snap: WeatherSnapshot) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                if settings.weatherShowLocation {
                    Text(snap.locality)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.42))
                        .lineLimit(1)
                }
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(
                        WeatherFormatting.temperatureLabel(
                            snap.temperatureC,
                            metric: metricTemp
                        )
                    )
                    .font(
                        .system(size: 34, weight: .semibold, design: .rounded)
                    )
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    Image(
                        systemName: WeatherSymbol.systemName(
                            code: snap.weatherCode,
                            isDay: snap.isDay
                        )
                    )
                    .font(.system(size: 20, weight: .regular))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white.opacity(0.88))
                }
                if showsMetaRow {
                    HStack(spacing: 10) {
                        if settings.weatherShowHighLow {
                            Text(
                                "H \(WeatherFormatting.temperatureLabel(snap.highC, metric: metricTemp))"
                            )
                            Text(
                                "L \(WeatherFormatting.temperatureLabel(snap.lowC, metric: metricTemp))"
                            )
                        }
                        if settings.weatherShowUV {
                            Text(WeatherFormatting.uvLabel(snap.uvIndex))
                        }
                        if settings.weatherShowWind {
                            Label {
                                Text(
                                    WeatherFormatting.windLabel(
                                        snap.windKmh,
                                        metric: metricWind
                                    )
                                )
                            } icon: {
                                Image(systemName: "wind")
                                    .font(.system(size: 9, weight: .semibold))
                            }
                            .labelStyle(.titleAndIcon)
                        }
                    }
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.4))
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var showsMetaRow: Bool {
        settings.weatherShowHighLow || settings.weatherShowUV
            || settings.weatherShowWind
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

    private func hours(_ snap: WeatherSnapshot) -> some View {
        let count = min(6, max(3, settings.weatherHourCount))
        let items = Array(snap.hours.prefix(count))
        return VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Hourly")
            HStack(spacing: 0) {
                if items.isEmpty {
                    ForEach(0..<count, id: \.self) { _ in
                        hourPlaceholder
                            .frame(maxWidth: .infinity)
                    }
                } else {
                    ForEach(Array(items.enumerated()), id: \.offset) {
                        _,
                        hour in
                        hourColumn(hour)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    private func hourColumn(_ hour: WeatherHour) -> some View {
        let showPrecip = settings.weatherShowPrecip && hour.precipChance >= 30
        return VStack(spacing: 6) {
            Text(WeatherFormatting.hourLabel(hour.date))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.36))
            Image(
                systemName: WeatherSymbol.systemName(
                    code: hour.weatherCode,
                    isDay: WeatherSymbol.isDay(at: hour.date)
                )
            )
            .font(.system(size: 15, weight: .regular))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(.white.opacity(0.88))
            .frame(height: 18)
            Text(
                WeatherFormatting.temperatureLabel(
                    hour.temperatureC,
                    metric: metricTemp
                )
            )
            .font(.system(size: 12, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(.white.opacity(0.9))
            if settings.weatherShowPrecip {
                Text(showPrecip ? "\(hour.precipChance)%" : " ")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.32))
                    .frame(height: 10)
            }
        }
    }

    private var hourPlaceholder: some View {
        VStack(spacing: 7) {
            Capsule().fill(.white.opacity(0.07)).frame(width: 22, height: 5)
            Circle().fill(.white.opacity(0.07)).frame(width: 13, height: 13)
            Capsule().fill(.white.opacity(0.07)).frame(width: 16, height: 7)
            if settings.weatherShowPrecip {
                Color.clear.frame(height: 10)
            }
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
