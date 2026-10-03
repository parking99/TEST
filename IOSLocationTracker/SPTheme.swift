//
//  SPTheme.swift
//  SecurityPass — طبقة العرض فقط
//
//  ألوان هوية «السعودية للطاقة» كما استُخرجت من ملف الشعار الرسمي
//  ومن متغيّرات CSS في se.com.sa. لا يعتمد هذا الملف على أي منطق
//  أو شبكة أو بروتوكول — ألوان وخطوط ومسافات فقط.
//

import SwiftUI

enum SP {

    // MARK: - الألوان

    enum Color {
        // أسطح
        static let ground      = SwiftUI.Color(hex: 0x001338)   // الأرضية
        static let navBar      = SwiftUI.Color(hex: 0x000F2C)   // شريط التبويب
        static let card        = SwiftUI.Color(hex: 0x00194B)   // البطاقة
        static let cardDim     = SwiftUI.Color(hex: 0x001540)   // بطاقة معطّلة
        static let raised      = SwiftUI.Color(hex: 0x002360)   // سطح مرتفع
        static let line        = SwiftUI.Color(hex: 0x163A77)   // الحد
        static let lineDim     = SwiftUI.Color(hex: 0x0E2A5E)
        static let lineStrong  = SwiftUI.Color(hex: 0x2B5496)

        // نصوص
        static let text        = SwiftUI.Color.white
        static let muted       = SwiftUI.Color(hex: 0x99A5BF)
        static let dim         = SwiftUI.Color(hex: 0x7589AD)
        static let dimmer      = SwiftUI.Color(hex: 0x4E6799)

        // الهوية
        static let accent      = SwiftUI.Color(hex: 0x80C0FF)   // لون الإشارة (نص وأزرار)
        static let corporate   = SwiftUI.Color(hex: 0x0066CC)   // الأزرق المؤسسي (تعبئة فقط)
        static let onAccent    = SwiftUI.Color(hex: 0x001338)   // النص فوق لون الإشارة

        // حالات
        static let ok          = SwiftUI.Color(hex: 0x00FF86)   // أخضر الشعار — متصل/نجاح
        static let okDeep      = SwiftUI.Color(hex: 0x00A86B)
        static let okSurface   = SwiftUI.Color(hex: 0x00263F)
        static let measure     = SwiftUI.Color(hex: 0x32C2FF)   // قياس
        static let danger      = SwiftUI.Color(hex: 0xFF393C)   // تعبئة SOS
        static let dangerText  = SwiftUI.Color(hex: 0xFF6163)   // نص/أيقونة خطر
        static let dangerLine  = SwiftUI.Color(hex: 0x99272B)
        static let dangerSurf  = SwiftUI.Color(hex: 0x2E0D12)
    }

    // MARK: - الخطوط
    //
    // الخط المؤسسي "SE Heartbeat" غير مضمّن في المشروع. أضف ملفاته إلى
    // Info.plist (UIAppFonts) ثم بدّل `custom` أدناه باسم العائلة الحقيقي؛
    // ما دام غير موجود، يسقط SwiftUI تلقائيًا على خط النظام.

    enum Font {
        static let family: String? = nil   // مثال: "SEHeartbeat"

        static func ui(_ size: CGFloat, _ weight: SwiftUI.Font.Weight = .regular) -> SwiftUI.Font {
            if let family { return .custom(family, size: size).weight(weight) }
            return .system(size: size, weight: weight)
        }

        /// للأرقام والقياسات — عرض ثابت حتى لا ترتجف القيمة أثناء التحديث الحي.
        static func numeric(_ size: CGFloat, _ weight: SwiftUI.Font.Weight = .medium) -> SwiftUI.Font {
            .system(size: size, weight: weight, design: .monospaced)
        }
    }

    // MARK: - المقاسات

    enum Metric {
        static let screenPadding: CGFloat = 20
        static let cardRadius: CGFloat    = 14
        static let heroRadius: CGFloat    = 18
        static let controlRadius: CGFloat = 12
        static let minTarget: CGFloat     = 44      // أصغر هدف لمس
        static let gap: CGFloat           = 16
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red:   Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8)  & 0xFF) / 255,
            blue:  Double( hex        & 0xFF) / 255,
            opacity: 1
        )
    }
}

// MARK: - تعديلات مشتركة

extension View {
    /// بطاقة السطح القياسية.
    func spCard(padding: CGFloat = 14, radius: CGFloat = SP.Metric.cardRadius) -> some View {
        self
            .padding(padding)
            .background(SP.Color.card)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(SP.Color.line, lineWidth: 1)
            )
    }

    /// تثبيت الاتجاه عربيًا بغضّ النظر عن لغة الجهاز.
    func spArabic() -> some View {
        self.environment(\.layoutDirection, .rightToLeft)
    }

    /// إخفاء لوحة المفاتيح بالسحب (متوافق مع iOS 15+)
    @ViewBuilder
    func spScrollDismissesKeyboard() -> some View {
        if #available(iOS 16.0, *) {
            self.scrollDismissesKeyboard(.interactively)
        } else {
            self
        }
    }
}
