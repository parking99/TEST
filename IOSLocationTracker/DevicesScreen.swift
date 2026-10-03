//
//  DevicesScreen.swift
//  SecurityPass — البحث والاقتران والتنشيط
//
//  يستدعي فقط: startScan / stopScan / connect(device:) / activateWatch /
//  forceUnbindAndReset، وهي الأسماء الموجودة في IdoSmartManager الحالي.
//

import SwiftUI

struct DevicesScreen: View {
    @ObservedObject var ido: IdoSmartManager
    @State private var showUnbindConfirm = false

    var body: some View {
        ScrollView {
            VStack(spacing: SP.Metric.gap) {

                scanCard

                if ido.isConnected {
                    pairingSteps
                }

                if ido.discoveredDevices.isEmpty {
                    emptyState
                } else {
                    deviceList
                }

                Button {
                    showUnbindConfirm = true
                } label: {
                    Label("فكّ ارتباط الساعة", systemImage: "trash")
                }
                .buttonStyle(SPDestructiveButton())
                .padding(.top, 6)
            }
            .padding(.horizontal, SP.Metric.screenPadding)
            .padding(.bottom, 24)
        }
        .safeAreaInset(edge: .top) {
            SPScreenHeader(kicker: "البحث عبر IDO SDK", title: "الأجهزة القريبة")
                .background(SP.Color.ground)
        }
        .confirmationDialog("فكّ ارتباط الساعة؟",
                            isPresented: $showUnbindConfirm, titleVisibility: .visible) {
            Button("فكّ الارتباط", role: .destructive) { ido.forceUnbindAndReset() }
            Button("إلغاء", role: .cancel) { }
        } message: {
            Text("ستحتاج إلى إعادة الاقتران من جديد قبل أن تستأنف القراءة.")
        }
    }

    // MARK: البحث

    private var scanCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 9) {
                Image(systemName: ido.isScanning ? "dot.radiowaves.left.and.right" : "magnifyingglass")
                    .foregroundStyle(ido.isScanning ? SP.Color.measure : SP.Color.muted)
                Text(ido.isScanning ? "جارٍ البحث عن السوار الذكي" : "تم إيقاف البحث")
                    .font(SP.Font.ui(13.5, .semibold))
                    .foregroundStyle(ido.isScanning ? SP.Color.text : SP.Color.muted)
                Spacer(minLength: 0)
                Text("\(ido.discoveredDevices.count)")
                    .font(SP.Font.numeric(11))
                    .foregroundStyle(SP.Color.muted)
            }

            progressTrack

            HStack(spacing: 9) {
                Button("بدء البحث") { ido.startScan() }
                    .buttonStyle(SPPrimaryButton())
                    .disabled(ido.isScanning)
                Button("إيقاف البحث") { ido.stopScan() }
                    .buttonStyle(SPSecondaryButton())
                    .disabled(!ido.isScanning)
            }
        }
        .spCard(padding: 16, radius: 16)
    }

    private var progressTrack: some View {
        HStack(spacing: 4) {
            ForEach(0..<6, id: \.self) { index in
                RoundedRectangle(cornerRadius: 3)
                    .fill(ido.isScanning && index < 2 ? SP.Color.measure : SP.Color.line)
                    .frame(height: 4)
            }
        }
    }

    // MARK: قائمة الأجهزة

    private var deviceList: some View {
        VStack(spacing: 10) {
            HStack {
                Text("الأجهزة المكتشفة بالقرب منك")
                    .font(SP.Font.ui(12, .semibold))
                    .foregroundStyle(SP.Color.muted)
                Spacer()
            }
            ForEach(ido.discoveredDevices) { device in
                deviceRow(device)
            }
        }
    }

    private func deviceRow(_ device: DiscoveredDevice) -> some View {
        let isCurrent = ido.isDeviceBound(macAddress: device.macAddress) || (device.macAddress == ido.currentDeviceUUID && !ido.currentDeviceUUID.isEmpty)

        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(device.name)
                        .font(SP.Font.ui(14, .semibold))
                        .foregroundStyle(SP.Color.text)
                    if isCurrent {
                        Text("مقترن سابقاً")
                            .font(SP.Font.ui(10, .semibold))
                            .foregroundStyle(SP.Color.ok)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(SP.Color.okDeep, lineWidth: 1))
                    }
                }
                Text(device.macAddress)
                    .font(SP.Font.numeric(11.5, .regular))
                    .foregroundStyle(SP.Color.muted)
                    .environment(\.layoutDirection, .leftToRight)
                HStack(spacing: 8) {
                    SPSignalBars(rssi: device.rssi)
                    Text("\(device.rssi) dBm")
                        .font(SP.Font.numeric(11, .regular))
                        .foregroundStyle(SP.Color.muted)
                        .environment(\.layoutDirection, .leftToRight)
                }
            }
            Spacer(minLength: 0)
            Button("اتصال") { ido.connect(device: device) }
                .font(SP.Font.ui(13, isCurrent ? .semibold : .medium))
                .foregroundStyle(isCurrent ? SP.Color.onAccent : SP.Color.text)
                .padding(.horizontal, 16)
                .frame(minHeight: SP.Metric.minTarget)
                .background(isCurrent ? SP.Color.ok : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(isCurrent ? Color.clear : SP.Color.lineStrong, lineWidth: 1)
                )
        }
        .padding(14)
        .background(SP.Color.card)
        .clipShape(RoundedRectangle(cornerRadius: SP.Metric.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SP.Metric.cardRadius, style: .continuous)
                .stroke(isCurrent ? SP.Color.ok : SP.Color.line, lineWidth: 1)
        )
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(SP.Color.dimmer)
                .frame(width: 72, height: 72)
                .background(SP.Color.cardDim)
                .clipShape(Circle())
                .overlay(Circle().stroke(SP.Color.line, lineWidth: 1))

            VStack(spacing: 9) {
                Text("لم يتم العثور على أجهزة بعد")
                    .font(SP.Font.ui(15, .semibold))
                    .foregroundStyle(SP.Color.text)
                Text("اضغط على زر البحث أعلاه لبدء المسح عبر البلوتوث.")
                    .font(SP.Font.ui(12.5))
                    .lineSpacing(4)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(SP.Color.muted)
            }

            VStack(alignment: .leading, spacing: 9) {
                hint("تأكد أن البلوتوث مفعّل وأن السوار قريب منك.")
                hint("السوار المتصل بتطبيق آخر لا يظهر في المسح.")
            }
            .padding(.top, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(SP.Color.lineStrong, style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
        )
    }

    private func hint(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Circle().fill(SP.Color.dimmer).frame(width: 5, height: 5).padding(.top, 6)
            Text(text).font(SP.Font.ui(12)).foregroundStyle(SP.Color.muted)
            Spacer(minLength: 0)
        }
    }

    // MARK: مراحل الاقتران

    private var pairingSteps: some View {
        VStack(alignment: .leading, spacing: 0) {
            step(1, "اتصال البلوتوث", "متصل بالسوار", done: ido.isConnected, last: false)
            step(2, "تنشيط الشاشة والحسّاسات",
                 ido.isActivated ? "المراقبة المستمرة تعمل الآن" : "بانتظار تفعيل الحسّاسات",
                 done: ido.isActivated, last: true)

            if !ido.isActivated {
                Button {
                    ido.activateWatch(force: true)
                } label: {
                    Label("أيقظ الساعة وحسّاساتها", systemImage: "rays")
                }
                .buttonStyle(SPPrimaryButton())
                .padding(.top, 12)
            }
        }
        .spCard(padding: 16, radius: 16)
    }

    private func step(_ index: Int, _ title: String, _ detail: String,
                      done: Bool, last: Bool) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .fill(done ? SP.Color.ok : Color.clear)
                        .overlay(Circle().stroke(done ? Color.clear : SP.Color.lineStrong, lineWidth: 2))
                        .frame(width: 28, height: 28)
                    if done {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(SP.Color.onAccent)
                    } else {
                        Text("\(index)")
                            .font(SP.Font.numeric(11, .semibold))
                            .foregroundStyle(SP.Color.muted)
                    }
                }
                if !last {
                    Rectangle().fill(done ? SP.Color.ok : SP.Color.line)
                        .frame(width: 2, height: 26)
                }
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(SP.Font.ui(14.5, .semibold))
                    .foregroundStyle(done ? SP.Color.text : SP.Color.muted)
                Text(detail)
                    .font(SP.Font.ui(12.5))
                    .lineSpacing(4)
                    .foregroundStyle(SP.Color.muted)
            }
            .padding(.bottom, last ? 0 : 14)
            Spacer(minLength: 0)
        }
    }
}
