public struct HistoryScreen: View {
    public let samples: [VitalSample]
    public var employeeID: String
    public var onSelect: (VitalSample) -> Void

    public init(samples: [VitalSample],
                employeeID: String,
                onSelect: @escaping (VitalSample) -> Void = { _ in }) {
        self.samples = samples
        self.employeeID = employeeID
        self.onSelect = onSelect
    }

    private var assessment: HealthAssessment { HealthEngine.assess(samples) }
    private var forecast: ForecastResult { HealthEngine.forecast(samples) }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                if assessment.isEmpty {
                    emptyState
                } else {
                    ScoreCard(assessment: assessment)
                    ForecastCard(forecast: forecast)
                    sectionTitle("المؤشرات الحيوية", trailing: "مقارنة بآخر ساعة")
                    metricsGrid
                    sectionTitle("سجل القراءات", trailing: nil)
                    readingsList
                }
                disclaimer
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(SP.Color.ground.ignoresSafeArea())
        .environment(\.layoutDirection, .rightToLeft)
    }

    // MARK: الأجزاء

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("تحليل آخر ٦ ساعات · \(employeeID)")
                .font(.system(size: 13))
                .foregroundColor(SP.Color.muted)
            Text("السجل الصحي")
                .font(.system(size: 30, weight: .bold))
                .foregroundColor(SP.Color.text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Text("لا يوجد سجل حتى الآن")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(SP.Color.text)
            Text("سيبدأ التقييم تلقائياً بعد وصول أول قراءات من السوار.")
                .font(.system(size: 13))
                .foregroundColor(SP.Color.muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .background(card)
    }

    private func sectionTitle(_ title: String, trailing: String?) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(SP.Color.text)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.system(size: 12))
                    .foregroundColor(SP.Color.muted)
            }
        }
    }

    private var metricsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12),
                            GridItem(.flexible(), spacing: 12)], spacing: 12) {
            ForEach(assessment.indicators.filter { $0.kind != .stability }, id: \.kind) { indicator in
                MetricCard(indicator: indicator, series: series(for: indicator.kind))
            }
        }
    }

    private var readingsList: some View {
        VStack(spacing: 0) {
            ForEach(Array(recentSamples.enumerated()), id: \.offset) { _, sample in
                Button { onSelect(sample) } label: {
                    ReadingRow(sample: sample)
                }
                .buttonStyle(.plain)
                Divider().overlay(SP.Color.raised)
            }
        }
        .background(card)
    }

    private var disclaimer: some View {
        Text("تقييم إرشادي لسلامة العامل الميداني، مبني على قراءات السوار فقط. ليس تشخيصاً طبياً ولا بديلاً عن مراجعة الطبيب.")
            .font(.system(size: 11))
            .lineSpacing(4)
            .foregroundColor(SP.Color.muted)
    }

    // MARK: بيانات مساعدة

    private var recentSamples: [VitalSample] {
        samples.sorted { $0.sampleDate > $1.sampleDate }.prefix(20).map { $0 }
    }

    private func series(for kind: VitalKind) -> [Double] {
        let sorted = samples.sorted { $0.sampleDate < $1.sampleDate }.suffix(40)
        switch kind {
        case .heartRate: return sorted.compactMap { $0.vHeartRate.map(Double.init) }
        case .spo2:      return sorted.compactMap { $0.vSpo2.map(Double.init) }
        case .bodyTemp:  return sorted.compactMap { $0.bodyTemp }
        case .pressure:  return sorted.compactMap { $0.systolic.map(Double.init) }
        case .stability: return []
        }
    }

    private var card: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(SP.Color.card)
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(SP.Color.raised, lineWidth: 1)
            )
    }
}

// MARK: - بطاقة التقييم العام

private struct ScoreCard: View {
    let assessment: HealthAssessment

    var body: some View {
        VStack(spacing: 16) {
            HStack(alignment: .center, spacing: 16) {
                ZStack {
                    Circle()
                        .stroke(SP.Color.raised, lineWidth: 12)
                    Circle()
                        .trim(from: 0, to: CGFloat(assessment.score) / 100)
                        .stroke(assessment.band.color,
                                style: StrokeStyle(lineWidth: 12, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 2) {
                        Text("\(assessment.score)")
                            .font(.system(size: 38, weight: .semibold, design: .monospaced))
                            .foregroundColor(SP.Color.text)
                        Text("من ١٠٠")
                            .font(.system(size: 11))
                            .foregroundColor(SP.Color.muted)
                    }
                }
                .frame(width: 124, height: 124)

                VStack(alignment: .leading, spacing: 8) {
                    StatusPill(text: assessment.band.title, color: assessment.band.color)
                    Text(assessment.headline)
                        .font(.system(size: 13))
                        .lineSpacing(4)
                        .foregroundColor(SP.Color.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            Divider().overlay(SP.Color.raised)

            HStack {
                stat("دقة التقييم", "\(Int(assessment.coverage * 100))%")
                Spacer()
                stat("القراءات", "\(assessment.sampleCount)")
                Spacer()
                stat("آخر تحديث", assessment.updatedAt.map(Self.time) ?? "—")
            }
        }
        .padding(18)
        .background(cardBackground(border: assessment.band.color.opacity(0.38)))
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(SP.Color.muted)
            Text(value)
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundColor(SP.Color.text)
        }
    }

    static func time(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ar_SA")
        f.dateFormat = "hh:mm a"
        return f.string(from: date)
    }
}

// MARK: - بطاقة التنبؤ

private struct ForecastCard: View {
    let forecast: ForecastResult

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label {
                    Text("التنبؤ · الساعة القادمة")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(SP.Color.text)
                } icon: {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .foregroundColor(SP.Color.caution)
                }
                Spacer()
                Text(confidenceLabel)
                    .font(.system(size: 11))
                    .foregroundColor(SP.Color.muted)
            }

            if forecast.insufficientCoverage {
                Text("تغطية القراءات غير كافية لإصدار تنبؤ. تأكد من اتصال السوار واستمرار الإرسال.")
                    .font(.system(size: 12))
                    .lineSpacing(4)
                    .foregroundColor(SP.Color.muted)
            } else if let top = forecast.risks.first {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("احتمال \(top.name)")
                            .font(.system(size: 14))
                            .foregroundColor(SP.Color.text)
                        Spacer()
                        Text("\(Int(top.probability * 100))%")
                            .font(.system(size: 16, weight: .semibold, design: .monospaced))
                            .foregroundColor(top.level.color)
                    }
                    ProgressBar(value: top.probability, color: top.level.color)
                    Text(top.why)
                        .font(.system(size: 12))
                        .lineSpacing(4)
                        .foregroundColor(SP.Color.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if forecast.risks.count > 1 {
                    Divider().overlay(SP.Color.raised)
                    HStack(spacing: 10) {
                        ForEach(forecast.risks.dropFirst().prefix(2)) { risk in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(risk.name)
                                    .font(.system(size: 11))
                                    .foregroundColor(SP.Color.muted)
                                HStack(spacing: 6) {
                                    Circle().fill(risk.level.color).frame(width: 7, height: 7)
                                    Text("\(Int(risk.probability * 100))%")
                                        .font(.system(size: 13, design: .monospaced))
                                        .foregroundColor(SP.Color.text)
                                    Text(risk.level.title)
                                        .font(.system(size: 11))
                                        .foregroundColor(SP.Color.muted)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }
        .padding(18)
        .background(cardBackground(border: SP.Color.raised))
    }

    private var confidenceLabel: String {
        switch forecast.coverage {
        case 0.8...: return "ثقة عالية"
        case 0.5..<0.8: return "ثقة متوسطة"
        default: return "ثقة منخفضة"
        }
    }
}

// MARK: - بطاقة مؤشر

private struct MetricCard: View {
    let indicator: IndicatorReading
    let series: [Double]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(indicator.kind.title)
                    .font(.system(size: 12))
                    .foregroundColor(SP.Color.muted)
                Spacer()
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundColor(indicator.band.color)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(indicator.display)
                    .font(.system(size: 28, weight: .semibold, design: .monospaced))
                    .foregroundColor(SP.Color.text)
                Text(indicator.kind.unit)
                    .font(.system(size: 11))
                    .foregroundColor(SP.Color.muted)
            }

            Sparkline(values: series)
                .stroke(indicator.band.color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .frame(height: 28)

            HStack(spacing: 6) {
                Text(indicator.band.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(indicator.band.color)
                if let trend = indicator.trend, abs(trend.slopePerMinute) > 0.001 {
                    Text(trend.slopePerMinute > 0 ? "صاعد" : "هابط")
                        .font(.system(size: 11))
                        .foregroundColor(SP.Color.muted)
                }
            }
        }
        .padding(14)
        .background(cardBackground(radius: 18, border: indicator.band == .normal
                                   ? SP.Color.raised
                                   : indicator.band.color.opacity(0.38)))
    }

    private var icon: String {
        switch indicator.kind {
        case .heartRate: return "heart"
        case .spo2: return "drop"
        case .bodyTemp: return "thermometer.medium"
        case .pressure: return "waveform.path.ecg"
        case .stability: return "chart.bar"
        }
    }
}

// MARK: - صف قراءة

private struct ReadingRow: View {
    let sample: VitalSample

    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(dotColor).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 3) {
                Text(ScoreCard.time(sample.sampleDate))
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundColor(SP.Color.text)
                Text(vitalsLine)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(SP.Color.muted)
            }
            Spacer()
            Image(systemName: "chevron.forward")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(SP.Color.muted)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
    }

    private var vitalsLine: String {
        var parts: [String] = []
        if let hr = sample.vHeartRate { parts.append("\(hr) bpm") }
        if let o = sample.vSpo2 { parts.append("\(o)%") }
        if let t = sample.bodyTemp { parts.append(String(format: "%.1f°", t)) }
        if let s = sample.systolic, let d = sample.diastolic { parts.append("\(s)/\(d)") }
        return parts.isEmpty ? "لا توجد قراءة — السوار غير متصل" : parts.joined(separator: " · ")
    }

    private var dotColor: Color {
        guard sample.vHeartRate != nil || sample.vSpo2 != nil else { return SP.Color.muted }
        let single = HealthEngine.assess([sample], now: sample.sampleDate)
        return single.band.color
    }
}

// MARK: - عناصر صغيرة

private struct StatusPill: View {
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(color)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 5)
        .background(
            Capsule().fill(color.opacity(0.14))
                .overlay(Capsule().stroke(color.opacity(0.38), lineWidth: 1))
        )
    }
}

private struct ProgressBar: View {
    let value: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(SP.Color.raised)
                Capsule().fill(color)
                    .frame(width: geo.size.width * CGFloat(min(max(value, 0), 1)))
            }
        }
        .frame(height: 8)
    }
}

private struct Sparkline: Shape {
    let values: [Double]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard values.count > 1,
              let min = values.min(), let max = values.max() else { return path }
        let span = max - min
        let stepX = rect.width / CGFloat(values.count - 1)

        for (i, v) in values.enumerated() {
            let ratio = span > 0 ? (v - min) / span : 0.5
            let point = CGPoint(x: CGFloat(i) * stepX,
                                y: rect.height - CGFloat(ratio) * rect.height)
            if i == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        return path
    }
}

private func cardBackground(radius: CGFloat = 20, border: Color) -> some View {
    RoundedRectangle(cornerRadius: radius, style: .continuous)
        .fill(SP.Color.card)
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .stroke(border, lineWidth: 1)
        )
}
