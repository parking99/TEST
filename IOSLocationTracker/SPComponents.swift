//
//  SPComponents.swift
//  SecurityPass — مكوّنات العرض المشتركة
//
//  لا شيء هنا يتصل بالبلوتوث أو بالشبكة. كل مكوّن يستقبل قيمًا جاهزة.
//

import SwiftUI

// MARK: - شارة الحالة

struct SPStatusPill: View {
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text)
                .font(SP.Font.ui(12, .semibold))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .background(SP.Color.card)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(SP.Color.line, lineWidth: 1))
    }
}

// MARK: - بطاقة قياس

struct SPMetricCard: View {
    let title: String
    let value: String
    var unit: String? = nil
    var icon: String
    var iconColor: Color = SP.Color.measure
    var isStale: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isStale ? SP.Color.dim : iconColor)
                Text(title)
                    .font(SP.Font.ui(11.5, .medium))
                    .foregroundStyle(isStale ? SP.Color.dim : SP.Color.muted)
                Spacer(minLength: 0)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(SP.Font.numeric(26))
                    .foregroundStyle(isStale ? SP.Color.dimmer : SP.Color.text)
                if let unit {
                    Text(unit)
                        .font(SP.Font.ui(11))
                        .foregroundStyle(SP.Color.muted)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isStale ? SP.Color.cardDim : SP.Color.card)
        .clipShape(RoundedRectangle(cornerRadius: SP.Metric.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SP.Metric.cardRadius, style: .continuous)
                .stroke(isStale ? SP.Color.lineDim : SP.Color.line, lineWidth: 1)
        )
    }
}

// MARK: - شريط النبض

/// شريط زخرفي يعبّر عن تدفّق القراءة الحيّة. الأعمدة الملوّنة هي الأحدث.
struct SPPulseStrip: View {
    var live: Bool = true
    private let heights: [CGFloat] = [9, 15, 7, 22, 11, 34, 13, 8, 19, 10, 28, 12, 7, 24,
                                      14, 38, 17, 9, 26, 12, 31, 15, 8, 21, 11, 35, 16, 10]

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(Array(heights.enumerated()), id: \.offset) { index, height in
                RoundedRectangle(cornerRadius: 2)
                    .fill(color(at: index))
                    .frame(width: 3, height: height)
            }
        }
        .frame(height: 40, alignment: .bottom)
        .accessibilityHidden(true)
    }

    private func color(at index: Int) -> Color {
        guard live else { return SP.Color.lineDim }
        if index >= 15 { return SP.Color.accent }
        return index % 3 == 0 ? SP.Color.lineStrong : SP.Color.line
    }
}

// MARK: - أعمدة قوة الإشارة

struct SPSignalBars: View {
    let rssi: Int

    private var filled: Int {
        switch rssi {
        case ..<(-85): return 1
        case ..<(-75): return 2
        case ..<(-62): return 3
        default:       return 4
        }
    }

    private var tint: Color {
        switch filled {
        case 1:  return SP.Color.dangerText
        case 2:  return SP.Color.accent
        default: return SP.Color.ok
        }
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(1...4, id: \.self) { step in
                RoundedRectangle(cornerRadius: 1)
                    .fill(step <= filled ? tint : SP.Color.lineStrong)
                    .frame(width: 3, height: CGFloat(step) * 3 + 2)
            }
        }
        .accessibilityLabel("قوة الإشارة \(filled) من 4")
    }
}

// MARK: - أنماط الأزرار

struct SPPrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(SP.Font.ui(14, .semibold))
            .foregroundStyle(SP.Color.onAccent)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(SP.Color.accent.opacity(configuration.isPressed ? 0.78 : 1))
            .clipShape(RoundedRectangle(cornerRadius: SP.Metric.controlRadius + 2, style: .continuous))
    }
}

struct SPSecondaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(SP.Font.ui(13.5, .medium))
            .foregroundStyle(SP.Color.text)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(configuration.isPressed ? SP.Color.raised : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: SP.Metric.controlRadius + 1, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: SP.Metric.controlRadius + 1, style: .continuous)
                    .stroke(SP.Color.lineStrong, lineWidth: 1)
            )
    }
}

struct SPDestructiveButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(SP.Font.ui(13, .semibold))
            .foregroundStyle(SP.Color.dangerText)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(configuration.isPressed ? SP.Color.dangerSurf : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: SP.Metric.controlRadius + 1, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: SP.Metric.controlRadius + 1, style: .continuous)
                    .stroke(SP.Color.dangerLine, lineWidth: 1)
            )
    }
}

/// زر SOS: النص أبيض بحجم كبير وعريض — وهو الشرط الذي يجعل التباين مقبولًا
/// فوق الأحمر. لا تصغّر مقاس الخط هنا.
struct SPEmergencyButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(SP.Font.ui(19, .bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 74)
            .background(SP.Color.danger.opacity(configuration.isPressed ? 0.82 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

/// بطاقة قابلة للضغط: انكماش خفيف عند اللمس بدل الوميض — يعطي إحساساً بأن البطاقة تُفتح.
struct SPPressableCard: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

// MARK: - رأس الشاشة

struct SPScreenHeader: View {
    let kicker: String
    let title: String
    var trailing: AnyView? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(kicker)
                    .font(SP.Font.ui(11, .medium))
                    .tracking(1.6)
                    .foregroundStyle(SP.Color.muted)
                Text(title)
                    .font(SP.Font.ui(25, .semibold))
                    .foregroundStyle(SP.Color.text)
            }
            Spacer(minLength: 0)
            if let trailing { trailing.padding(.top, 4) }
        }
        .padding(.horizontal, SP.Metric.screenPadding)
        .padding(.top, 8)
        .padding(.bottom, 16)
    }
}

// MARK: - صف معلومة

struct SPInfoRow: View {
    let label: String
    let value: String
    var valueColor: Color = SP.Color.text
    var monospaced: Bool = true

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(SP.Font.ui(12.5))
                .foregroundStyle(SP.Color.muted)
            Spacer(minLength: 0)
            Text(value)
                .font(monospaced ? SP.Font.numeric(13) : SP.Font.ui(13, .semibold))
                .foregroundStyle(valueColor)
                .environment(\.layoutDirection, .leftToRight)
        }
        .padding(.vertical, 12)
    }
}
