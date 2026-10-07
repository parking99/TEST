//
//  HealthReportPDF.swift
//  SecurityPass
//
//  مولّد تقرير PDF متعدد الصفحات — رسم مباشر بـ Core Graphics.
//  النص متجهي قابل للتحديد والبحث والطباعة بوضوح، لا لقطة شاشة.
//  ألوان الطباعة نسخ داكنة من ألوان الشاشة: الأخضر النيون على أبيض غير مقروء.
//

import UIKit

public enum HealthReportPDF {

    // MARK: ألوان الطباعة

    private enum Ink {
        static let text      = UIColor(red: 0.00, green: 0.07, blue: 0.22, alpha: 1)  // #001338
        static let muted     = UIColor(red: 0.35, green: 0.40, blue: 0.51, alpha: 1)  // #5A6682
        static let rule      = UIColor(red: 0.89, green: 0.91, blue: 0.94, alpha: 1)  // #E2E7F0
        static let cardFill  = UIColor(red: 0.96, green: 0.97, blue: 0.98, alpha: 1)  // #F5F7FB
        static let accent    = UIColor(red: 0.09, green: 0.23, blue: 0.47, alpha: 1)  // #163A77
        static let success   = UIColor(red: 0.05, green: 0.48, blue: 0.27, alpha: 1)  // #0E7A45
        static let caution   = UIColor(red: 0.66, green: 0.36, blue: 0.00, alpha: 1)  // #A85C00
        static let danger    = UIColor(red: 0.75, green: 0.12, blue: 0.16, alpha: 1)  // #C01F28
    }

    private static func color(_ band: VitalBand) -> UIColor {
        switch band {
        case .normal:   return Ink.success
        case .caution:  return Ink.caution
        case .critical: return Ink.danger
        case .unknown:  return Ink.muted
        }
    }

    private static func color(_ band: HealthBand) -> UIColor {
        switch band {
        case .excellent: return Ink.success
        case .good:      return Ink.accent
        case .attention: return Ink.caution
        case .danger:    return Ink.danger
        }
    }

    private static func title(_ band: VitalBand) -> String {
        switch band {
        case .normal:   return "طبيعي"
        case .caution:  return "خارج النطاق"
        case .critical: return "تجاوز الحد"
        case .unknown:  return "—"
        }
    }

    // MARK: قياسات الصفحة

    private static let page = CGRect(x: 0, y: 0, width: 595.2, height: 841.8)   // A4
    private static let margin: CGFloat = 40
    private static let rowHeight: CGFloat = 18
    private static let rowsPerPage = 36

    private static var contentWidth: CGFloat { page.width - margin * 2 }

    // MARK: الواجهة

    /// ينتج ملف PDF في مجلد مؤقت ويعيد مساره، جاهزاً للمشاركة.
    public static func render(_ report: HealthReport) throws -> URL {
        let readingPages = report.readings.isEmpty
            ? 0
            : Int(ceil(Double(report.readings.count) / Double(rowsPerPage)))
        let totalPages = 1 + readingPages

        let info: [String: Any] = [
            kCGPDFContextTitle as String: "التقرير الصحي — \(report.employeeID)",
            kCGPDFContextCreator as String: "SecurityPass"
        ]

        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = info

        let renderer = UIGraphicsPDFRenderer(bounds: page, format: format)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(fileName(for: report))

        try renderer.writePDF(to: url) { ctx in
            ctx.beginPage()
            drawSummaryPage(report)
            drawFooter(page: 1, of: totalPages, report: report)

            for index in 0..<readingPages {
                ctx.beginPage()
                drawReadingsPage(report, pageIndex: index)
                drawFooter(page: index + 2, of: totalPages, report: report)
            }
        }
        return url
    }

    public static func fileName(for report: HealthReport) -> String {
        let stamp = ReportFormat.fileStamp.string(from: report.generatedAt)
        let id = report.employeeID.replacingOccurrences(of: " ", with: "_")
        return "SecurityPass_Health_\(id)_\(stamp).pdf"
    }

    // MARK: الصفحة الأولى

    private static func drawSummaryPage(_ report: HealthReport) {
        var y = drawHeader(report)
        y = drawScoreBlock(report, top: y + 18)
        y = drawIndicatorGrid(report, top: y + 18)
        y = drawChart(report, top: y + 18)
        _ = drawDailyTable(report, top: y + 18)
    }

    private static func drawHeader(_ report: HealthReport) -> CGFloat {
        Ink.accent.setFill()
        UIBezierPath(rect: CGRect(x: 0, y: 0, width: page.width, height: 6)).fill()

        var y: CGFloat = margin + 6
        text("التقرير الصحي", CGRect(x: margin, y: y, width: contentWidth, height: 30),
             font: .systemFont(ofSize: 24, weight: .bold), color: Ink.text)
        y += 30

        text("SecurityPass · المعرف الوظيفي \(report.employeeID)",
             CGRect(x: margin, y: y, width: contentWidth, height: 18),
             font: .systemFont(ofSize: 12), color: Ink.muted)
        y += 18

        let range = "\(ReportFormat.dayMonth.string(from: report.from)) — \(ReportFormat.dayMonth.string(from: report.to))"
        text("\(report.period.title) · \(range) · \(report.assessment.sampleCount) قراءة",
             CGRect(x: margin, y: y, width: contentWidth, height: 18),
             font: .systemFont(ofSize: 12), color: Ink.muted)
        y += 22

        Ink.rule.setFill()
        UIBezierPath(rect: CGRect(x: margin, y: y, width: contentWidth, height: 1)).fill()

        return y
    }

    private static func drawScoreBlock(_ report: HealthReport, top: CGFloat) -> CGFloat {
        let height: CGFloat = 92
        let rect = CGRect(x: margin, y: top, width: contentWidth, height: height)
        card(rect)

        let a = report.assessment
        let accent = color(a.band)

        // شريط لوني على الحافة اليمنى (اتجاه القراءة)
        accent.setFill()
        UIBezierPath(roundedRect: CGRect(x: rect.maxX - 5, y: rect.minY, width: 5, height: height),
                     cornerRadius: 2.5).fill()

        let pad: CGFloat = 16
        var y = rect.minY + pad
        text("التقييم العام للفترة",
             CGRect(x: rect.minX + pad, y: y, width: rect.width - pad * 2 - 8, height: 14),
             font: .systemFont(ofSize: 11), color: Ink.muted)
        y += 16

        text("\(a.score)", CGRect(x: rect.maxX - 150, y: y, width: 130, height: 34),
             font: .monospacedDigitSystemFont(ofSize: 30, weight: .bold), color: Ink.text)

        text("من ١٠٠ · \(a.band.title)",
             CGRect(x: rect.minX + pad, y: y + 10, width: rect.width - 180, height: 18),
             font: .systemFont(ofSize: 13, weight: .semibold), color: accent)
        y += 38

        text(a.headline,
             CGRect(x: rect.minX + pad, y: y, width: rect.width - pad * 2 - 8, height: 32),
             font: .systemFont(ofSize: 11), color: Ink.text, lines: 2)

        return rect.maxY
    }

    private static func drawIndicatorGrid(_ report: HealthReport, top: CGFloat) -> CGFloat {
        guard !report.summary.isEmpty else { return top }

        let columns = 4
        let gap: CGFloat = 8
        let w = (contentWidth - gap * CGFloat(columns - 1)) / CGFloat(columns)
        let h: CGFloat = 74

        var maxY = top
        for (i, s) in report.summary.enumerated() {
            let row = i / columns
            let col = i % columns

            // RTL: العمود الأول على اليمين
            let x = margin + CGFloat(columns - 1 - col) * (w + gap)
            let y = top + CGFloat(row) * (h + gap)

            let rect = CGRect(x: x, y: y, width: w, height: h)
            card(rect)

            let pad: CGFloat = 9
            let inner = CGRect(x: rect.minX + pad, y: rect.minY + pad,
                               width: rect.width - pad * 2, height: 0)

            text(s.kind.title, inner.offsetBy(dx: 0, dy: 0).with(height: 12),
                 font: .systemFont(ofSize: 9.5), color: Ink.muted)

            text("\(s.latest) \(s.kind.unit)",
                 inner.offsetBy(dx: 0, dy: 13).with(height: 20),
                 font: .monospacedDigitSystemFont(ofSize: 15, weight: .semibold), color: Ink.text)

            text(title(s.band),
                 inner.offsetBy(dx: 0, dy: 33).with(height: 12),
                 font: .systemFont(ofSize: 8.5, weight: .semibold), color: color(s.band))

            text("أدنى \(s.minimum) · وسط \(s.average) · أعلى \(s.maximum)",
                 inner.offsetBy(dx: 0, dy: 46).with(height: 11),
                 font: .systemFont(ofSize: 7), color: Ink.muted)

            text("ضمن النطاق \(Int((s.inRange * 100).rounded()))% من الوقت",
                 inner.offsetBy(dx: 0, dy: 56).with(height: 11),
                 font: .systemFont(ofSize: 7), color: Ink.muted)

            maxY = max(maxY, rect.maxY)
        }
        return maxY
    }

    private static func drawChart(_ report: HealthReport, top: CGFloat) -> CGFloat {
        let series = report.heartRateSeries.map { $0.value }
        guard series.count >= 2 else { return top }

        let height: CGFloat = 130
        let rect = CGRect(x: margin, y: top, width: contentWidth, height: height)

        text("مسار نبض القلب خلال الفترة",
             CGRect(x: margin, y: top, width: contentWidth, height: 14),
             font: .systemFont(ofSize: 11, weight: .semibold), color: Ink.text)

        let plot = CGRect(x: rect.minX + 34, y: rect.minY + 22,
                          width: rect.width - 34, height: height - 36)

        let lo = min(series.min() ?? 60, 55)
        let hi = max(series.max() ?? 120, 125)
        let span = max(hi - lo, 1)

        func yFor(_ v: Double) -> CGFloat {
            plot.maxY - CGFloat((v - lo) / span) * plot.height
        }

        // النطاق الآمن ٦٠–١٠٠
        Ink.success.withAlphaComponent(0.10).setFill()
        let bandRect = CGRect(x: plot.minX, y: yFor(100),
                              width: plot.width, height: yFor(60) - yFor(100))
        UIBezierPath(rect: bandRect).fill()

        // خط الإنذار ١٢٠
        let alarm = UIBezierPath()
        alarm.move(to: CGPoint(x: plot.minX, y: yFor(120)))
        alarm.addLine(to: CGPoint(x: plot.maxX, y: yFor(120)))
        alarm.setLineDash([3, 3], count: 2, phase: 0)
        alarm.lineWidth = 0.8
        Ink.danger.setStroke()
        alarm.stroke()

        for value in [120.0, 100.0, 60.0] {
            text("\(Int(value))",
                 CGRect(x: rect.minX, y: yFor(value) - 7, width: 28, height: 12),
                 font: .monospacedDigitSystemFont(ofSize: 8, weight: .regular),
                 color: value == 120 ? Ink.danger : Ink.muted, align: .left)
        }

        // المنحنى — تخفيف الكثافة ليبقى مقروءاً
        let step = max(1, series.count / 220)
        let points = stride(from: 0, to: series.count, by: step).map { i -> CGPoint in
            let x = plot.minX + plot.width * CGFloat(i) / CGFloat(max(series.count - 1, 1))
            return CGPoint(x: x, y: yFor(series[i]))
        }

        let line = UIBezierPath()
        for (i, p) in points.enumerated() {
            if i == 0 {
                line.move(to: p)
            } else {
                line.addLine(to: p)
            }
        }
        line.lineWidth = 1.4
        line.lineJoinStyle = .round
        line.lineCapStyle = .round
        Ink.accent.setStroke()
        line.stroke()

        Ink.rule.setFill()
        UIBezierPath(rect: CGRect(x: plot.minX, y: plot.maxY, width: plot.width, height: 0.7)).fill()

        text(ReportFormat.dayMonth.string(from: report.to),
             CGRect(x: plot.minX, y: plot.maxY + 3, width: 120, height: 11),
             font: .systemFont(ofSize: 8), color: Ink.muted)
        text(ReportFormat.dayMonth.string(from: report.from),
             CGRect(x: plot.maxX - 120, y: plot.maxY + 3, width: 120, height: 11),
             font: .systemFont(ofSize: 8), color: Ink.muted, align: .left)

        return rect.maxY
    }

    private static func drawDailyTable(_ report: HealthReport, top: CGFloat) -> CGFloat {
        guard !report.daily.isEmpty else { return top }

        var y = top
        text("ملخص يومي",
             CGRect(x: margin, y: y, width: contentWidth, height: 14),
             font: .systemFont(ofSize: 11, weight: .semibold), color: Ink.text)
        y += 20

        let widths: [CGFloat] = [96, 62, 62, 82, 72, 78, 63]
        let headers = ["التاريخ", "القراءات", "التقييم", "متوسط النبض", "أعلى نبض", "أدنى أكسجين", "أعلى حرارة"]
        y = drawTableHeader(headers, widths: widths, top: y)

        let limit = min(report.daily.count, 12)
        for stat in report.daily.prefix(limit) {
            let cells = columns(widths: widths, top: y)
            let font = UIFont.systemFont(ofSize: 9.5)
            let mono = UIFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .regular)

            text(ReportFormat.dayMonth.string(from: stat.day), cells[0], font: font, color: Ink.text)
            text("\(stat.count)", cells[1], font: mono, color: Ink.muted)
            text("\(stat.score)", cells[2], font: mono, color: color(stat.band))
            text(stat.avgHeartRate.map { "\(Int($0.rounded()))" } ?? "—", cells[3], font: mono, color: Ink.text)
            text(stat.maxHeartRate.map { "\(Int($0.rounded()))" } ?? "—", cells[4], font: mono, color: Ink.text)
            text(stat.minSpo2.map { "\(Int($0.rounded()))%" } ?? "—", cells[5], font: mono, color: Ink.text)
            text(stat.maxTemp.map { String(format: "%.1f", $0) } ?? "—", cells[6], font: mono, color: Ink.text)

            y += rowHeight
            rule(at: y)
        }

        if report.daily.count > limit {
            text("وأيام أخرى — التفصيل الكامل في سجل القراءات",
                 CGRect(x: margin, y: y + 4, width: contentWidth, height: 12),
                 font: .systemFont(ofSize: 9), color: Ink.muted)
            y += 18
        }
        return y
    }

    // MARK: صفحات سجل القراءات

    private static func drawReadingsPage(_ report: HealthReport, pageIndex: Int) {
        var y: CGFloat = margin
        let start = pageIndex * rowsPerPage
        let end = min(start + rowsPerPage, report.readings.count)

        text("سجل القراءات", CGRect(x: margin, y: y, width: contentWidth, height: 20),
             font: .systemFont(ofSize: 15, weight: .semibold), color: Ink.text)
        y += 20

        var caption = "القراءات \(start + 1)–\(end) من \(report.readings.count) · الأحدث أولاً"
        if report.isTruncated {
            caption += " · أحدث \(report.readings.count) قراءة من أصل \(report.readingsTotal)"
        }
        text(caption, CGRect(x: margin, y: y, width: contentWidth, height: 14),
             font: .systemFont(ofSize: 10), color: Ink.muted)
        y += 22

        let widths: [CGFloat] = [104, 72, 78, 92, 82, 87]
        y = drawTableHeader(["الوقت", "النبض", "الأكسجين", "الضغط", "الحرارة", "الحالة"],
                            widths: widths, top: y)

        for reading in report.readings[start..<end] {
            let cells = columns(widths: widths, top: y)
            let mono = UIFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .regular)

            text(ReportFormat.time.string(from: reading.date), cells[0], font: mono, color: Ink.text)
            text(reading.heartRate, cells[1], font: mono, color: Ink.text)
            text(reading.spo2, cells[2], font: mono, color: Ink.text)
            text(reading.pressure, cells[3], font: mono, color: Ink.text)
            text(reading.temperature, cells[4], font: mono, color: Ink.text)
            text(reading.band.title, cells[5],
                 font: .systemFont(ofSize: 9.5, weight: .medium), color: color(reading.band))

            y += rowHeight
            rule(at: y)
        }
    }

    // MARK: التذييل

    private static func drawFooter(page pageNumber: Int, of total: Int, report: HealthReport) {
        let y = page.height - margin - 26
        Ink.rule.setFill()
        UIBezierPath(rect: CGRect(x: margin, y: y, width: contentWidth, height: 0.7)).fill()

        text("تقرير إرشادي لسلامة العامل الميداني، مبني على قراءات السوار. ليس تشخيصاً طبياً.",
             CGRect(x: margin, y: y + 7, width: contentWidth - 90, height: 12),
             font: .systemFont(ofSize: 8), color: Ink.muted)

        text("صفحة \(pageNumber) من \(total)",
             CGRect(x: page.width - margin - 90, y: y + 7, width: 90, height: 12),
             font: .systemFont(ofSize: 8), color: Ink.muted, align: .left)

        text("أُنشئ في \(ReportFormat.full.string(from: report.generatedAt))",
             CGRect(x: margin, y: y + 19, width: contentWidth, height: 12),
             font: .systemFont(ofSize: 8), color: Ink.muted)
    }

    // MARK: أدوات الرسم

    private static func drawTableHeader(_ titles: [String], widths: [CGFloat], top: CGFloat) -> CGFloat {
        let cells = columns(widths: widths, top: top)
        for (i, t) in titles.enumerated() where i < cells.count {
            text(t, cells[i], font: .systemFont(ofSize: 9, weight: .semibold), color: Ink.muted)
        }

        let y = top + 15
        Ink.rule.setFill()
        UIBezierPath(rect: CGRect(x: margin, y: y, width: contentWidth, height: 0.7)).fill()

        return y + 4
    }

    /// أعمدة من اليمين إلى اليسار.
    private static func columns(widths: [CGFloat], top: CGFloat) -> [CGRect] {
        var x = page.width - margin
        return widths.map { w in
            x -= w
            return CGRect(x: x, y: top, width: w, height: rowHeight - 3)
        }
    }

    private static func rule(at y: CGFloat) {
        Ink.rule.setFill()
        UIBezierPath(rect: CGRect(x: margin, y: y - 3, width: contentWidth, height: 0.5)).fill()
    }

    private static func card(_ rect: CGRect) {
        Ink.cardFill.setFill()
        Ink.rule.setStroke()
        let path = UIBezierPath(roundedRect: rect, cornerRadius: 8)
        path.fill()
        path.lineWidth = 0.7
        path.stroke()
    }

    private static func text(_ string: String, _ rect: CGRect,
                             font: UIFont, color: UIColor,
                             align: NSTextAlignment = .right, lines: Int = 1) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = align
        paragraph.baseWritingDirection = .rightToLeft
        paragraph.lineBreakMode = lines == 1 ? .byTruncatingTail : .byWordWrapping
        paragraph.lineSpacing = lines == 1 ? 0 : 2

        (string as NSString).draw(in: rect, withAttributes: [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ])
    }
}

private extension CGRect {
    func with(height newHeight: CGFloat) -> CGRect {
        CGRect(x: minX, y: minY, width: width, height: newHeight)
    }
}
