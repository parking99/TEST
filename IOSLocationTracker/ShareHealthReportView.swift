//
//  ShareHealthReportView.swift
//  SecurityPass
//
//  شاشة مشاركة الوضع الصحي: اختيار الفترة، معاينة، ثم إنشاء PDF ومشاركته.
//  تحل محل ورقة المشاركة النصية الحالية.
//

import SwiftUI
import UIKit

public struct ShareHealthReportView: View {
    public let samples: [VitalSample]
    public let employeeID: String

    @State private var period: ReportPeriod = .week
    @State private var report: HealthReport?
    @State private var isPreparing = true
    @State private var isBuilding = false
    @State private var payload: SharePayload?
    @State private var failure: String?
    @Environment(\.presentationMode) private var presentation

    public init(samples: [VitalSample], employeeID: String) {
        self.samples = samples
        self.employeeID = employeeID
    }

    public var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    periodPicker

                    if isPreparing {
                        placeholder("جارٍ تجهيز الملخص…")
                    } else if let report = report, !report.isEmpty {
                        summaryCard(report)
                        contentsCard(report)
                    } else {
                        placeholder("لا توجد قراءات في هذه الفترة.")
                    }

                    shareButton

                    if let failure = failure {
                        Text(failure)
                            .font(.system(size: 12))
                            .foregroundColor(SP.Color.dangerText)
                    }

                    Text("يُنشأ الملف على جهازك ويُشارك عبر قائمة المشاركة. لا يُرفع إلى أي خادم.")
                        .font(.system(size: 11))
                        .lineSpacing(3)
                        .foregroundColor(SP.Color.muted)
                }
                .padding(20)
            }
            .background(SP.Color.ground.ignoresSafeArea())
            .navigationBarTitle("مشاركة الوضع الصحي", displayMode: .inline)
            .navigationBarItems(trailing: Button("إغلاق") {
                presentation.wrappedValue.dismiss()
            })
        }
        .environment(\.layoutDirection, .rightToLeft)
        .onAppear(perform: rebuild)
        .onChange(of: period) { _ in rebuild() }
        .sheet(item: $payload) { item in
            ActivityView(url: item.url)
        }
    }

    // MARK: الأجزاء

    private var periodPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("الفترة")
                .font(.system(size: 12))
                .foregroundColor(SP.Color.muted)

            Picker("الفترة", selection: $period) {
                ForEach(ReportPeriod.allCases) { p in
                    Text(p.title).tag(p)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundColor(SP.Color.muted)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
            .background(cardShape)
    }

    private func summaryCard(_ report: HealthReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(report.assessment.score)")
                    .font(.system(size: 30, weight: .semibold, design: .monospaced))
                    .foregroundColor(SP.Color.text)
                Text("من ١٠٠ · \(report.assessment.band.title)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(SP.Color.accent)
                Spacer(minLength: 0)
            }
            Text(report.assessment.headline)
                .font(.system(size: 12))
                .lineSpacing(4)
                .foregroundColor(SP.Color.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardShape)
    }

    private func contentsCard(_ report: HealthReport) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("محتويات التقرير")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(SP.Color.text)

            bullet("التقييم العام وتفسيره")
            bullet("ملخص كل مؤشر: الأدنى والمتوسط والأعلى ونسبة الوقت ضمن النطاق")
            bullet("مسار نبض القلب خلال الفترة")
            bullet("ملخص يومي لـ \(report.daily.count) يوم")
            bullet(report.isTruncated
                   ? "سجل بأحدث \(report.readings.count) قراءة من أصل \(report.readingsTotal)"
                   : "سجل كامل بـ \(report.readings.count) قراءة")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardShape)
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(SP.Color.accent)
                .frame(width: 5, height: 5)
                .padding(.top, 6)

            Text(text)
                .font(.system(size: 12))
                .lineSpacing(3)
                .foregroundColor(SP.Color.muted)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private var shareButton: some View {
        let ready = !(report?.isEmpty ?? true) && !isPreparing

        return Button(action: build) {
            HStack(spacing: 8) {
                if isBuilding {
                    ProgressView().tint(SP.Color.ground)
                } else {
                    Image(systemName: "square.and.arrow.up")
                }
                Text(isBuilding ? "جارٍ إنشاء الملف…" : "إنشاء PDF ومشاركته")
                    .font(.system(size: 15, weight: .semibold))
            }
            .frame(maxWidth: .infinity, minHeight: 50)
            .foregroundColor(SP.Color.ground)
            .background(SP.Color.accent)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .disabled(isBuilding || !ready)
        .opacity(ready ? 1 : 0.4)
    }

    private var cardShape: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(SP.Color.card)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(SP.Color.raised, lineWidth: 1)
            )
    }

    // MARK: البناء

    /// تقرير شهر قد يحمل عشرات الآلاف من القراءات — التجميع والرسم خارج الخيط الرئيسي.
    private func rebuild() {
        isPreparing = true
        failure = nil
        let snapshot = samples
        let id = employeeID
        let selected = period

        DispatchQueue.global(qos: .userInitiated).async {
            let built = HealthReportBuilder.build(from: snapshot, employeeID: id, period: selected)
            DispatchQueue.main.async {
                guard selected == period else { return }   // تجاهل نتيجة فترة قديمة
                report = built
                isPreparing = false
            }
        }
    }

    private func build() {
        guard let snapshot = report else { return }

        isBuilding = true
        failure = nil

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let url = try HealthReportPDF.render(snapshot)
                DispatchQueue.main.async {
                    isBuilding = false
                    payload = SharePayload(url: url)
                }
            } catch {
                DispatchQueue.main.async {
                    isBuilding = false
                    failure = "تعذّر إنشاء الملف. حاول مرة أخرى."
                }
            }
        }
    }
}

private struct SharePayload: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

// MARK: - قائمة المشاركة

private struct ActivityView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {
        // التطبيق يدعم iPad (UIDeviceFamily = 1,2) — بلا مصدر للـ popover ينهار هناك.
        guard let popover = controller.popoverPresentationController, popover.sourceView == nil else { return }
        popover.sourceView = controller.view
        popover.permittedArrowDirections = []
        popover.sourceRect = CGRect(x: controller.view.bounds.midX,
                                    y: controller.view.bounds.midY,
                                    width: 1, height: 1)
    }
}
