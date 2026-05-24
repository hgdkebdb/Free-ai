import SwiftUI

// Главный экран приложения "Metal & Wire Detector"
struct ContentView: View {

    @StateObject private var magnetometer = MagnetometerManager()

    // Фаза жизненного цикла сцены — для остановки датчика в фоне
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)

            VStack(spacing: 20) {
                Text("Metal & Wire Detector")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.top, 40)

                modePicker

                // Баннеры с подсказками — приоритет у проблемы с точностью
                if magnetometer.isAvailable {
                    if let hint = magnetometer.accuracy.hintText {
                        hintBanner(text: hint, icon: "exclamationmark.triangle.fill", color: .yellow)
                    } else if magnetometer.mode == .liveWire && magnetometer.isPhoneMoving {
                        hintBanner(text: "Держите телефон неподвижно у стены",
                                   icon: "hand.raised.fill",
                                   color: .orange)
                    }
                }

                Spacer()

                if !magnetometer.isAvailable {
                    Text("Магнитометр недоступен\nна этом устройстве")
                        .font(.headline)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                } else {
                    detectorGauge
                    statusText
                }

                Spacer()

                calibrationButton
                    .padding(.bottom, 40)
            }
            .padding(.horizontal, 20)
        }
        .onAppear {
            magnetometer.startUpdates()
        }
        .onDisappear {
            magnetometer.stopUpdates()
        }
        .onChange(of: scenePhase) { phase in
            // Энергосбережение: 100 Гц на датчике сильно греет процессор и сажает батарею.
            // В фоне или при сворачивании останавливаем, при активации возобновляем.
            switch phase {
            case .active:
                magnetometer.startUpdates()
            case .inactive, .background:
                magnetometer.stopUpdates()
            @unknown default:
                break
            }
        }
    }

    // MARK: - Переключатель режимов

    private var modePicker: some View {
        Picker("Режим", selection: $magnetometer.mode) {
            ForEach(DetectorMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 4)
    }

    // MARK: - Универсальный баннер-подсказка

    private func hintBanner(text: String, icon: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(color)
            Text(text)
                .font(.footnote)
                .foregroundColor(.white)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(color.opacity(0.15))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(color.opacity(0.5), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Текущее значение, шкала и форматирование

    private var currentValue: Double {
        switch magnetometer.mode {
        case .metal:    return magnetometer.magneticFieldStrength
        case .liveWire: return magnetometer.acAmplitude
        }
    }

    private var maxScaleValue: Double {
        switch magnetometer.mode {
        case .metal:    return 200.0
        case .liveWire: return 10.0
        }
    }

    private var thresholds: (low: Double, high: Double) {
        switch magnetometer.mode {
        case .metal:    return (70.0, 120.0)
        case .liveWire: return (1.0, 3.0)
        }
    }

    // В режиме провода значения мелкие — даём две цифры после запятой.
    private var valueFormat: String {
        switch magnetometer.mode {
        case .metal:    return "%.1f"
        case .liveWire: return "%.2f"
        }
    }

    // MARK: - Круглый индикатор

    private var detectorGauge: some View {
        ZStack {
            Circle()
                .stroke(Color.gray.opacity(0.3), lineWidth: 20)

            Circle()
                .trim(from: 0.0, to: CGFloat(min(currentValue / maxScaleValue, 1.0)))
                .stroke(
                    gaugeColor,
                    style: StrokeStyle(lineWidth: 20, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.2), value: currentValue)

            VStack(spacing: 4) {
                Text(String(format: valueFormat, currentValue))
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .monospacedDigit()
                Text(unitLabel)
                    .font(.title3)
                    .foregroundColor(.gray)
            }
        }
        .frame(width: 260, height: 260)
    }

    private var unitLabel: String {
        switch magnetometer.mode {
        case .metal:    return "μT"
        case .liveWire: return "μT (AC)"
        }
    }

    private var gaugeColor: Color {
        let (low, high) = thresholds
        switch currentValue {
        case ..<low:     return .green
        case low..<high: return .yellow
        default:         return .red
        }
    }

    // MARK: - Текстовый статус

    private var statusText: some View {
        let (low, high) = thresholds
        let value = currentValue
        let (text, color): (String, Color)

        switch magnetometer.mode {
        case .metal:
            switch value {
            case ..<low:
                text = "Стена чиста / Металл не обнаружен"
                color = .green
            case low..<high:
                text = "Подозрение на металл/проводку"
                color = .yellow
            default:
                text = "ВНИМАНИЕ! Обнаружен металл или кабель!"
                color = .red
            }
        case .liveWire:
            switch value {
            case ..<low:
                text = "Кабелей под напряжением не обнаружено"
                color = .green
            case low..<high:
                text = "Возможен провод под напряжением"
                color = .yellow
            default:
                text = "ВНИМАНИЕ! Кабель под напряжением!"
                color = .red
            }
        }

        return Text(text)
            .font(.headline)
            .foregroundColor(color)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
    }

    // MARK: - Кнопка калибровки фона

    private var calibrationButton: some View {
        Button(action: {
            magnetometer.calibrate()
        }) {
            HStack {
                Image(systemName: "scope")
                Text(calibrationButtonTitle)
                    .fontWeight(.semibold)
            }
            .foregroundColor(.white)
            .padding(.vertical, 14)
            .padding(.horizontal, 40)
            .background(calibrationButtonEnabled ? Color.blue : Color.gray)
            .clipShape(Capsule())
        }
        .disabled(!calibrationButtonEnabled)
    }

    private var calibrationButtonEnabled: Bool {
        magnetometer.isAvailable
            && magnetometer.mode == .metal
            && !magnetometer.accuracy.needsCalibrationHint
    }

    private var calibrationButtonTitle: String {
        switch magnetometer.mode {
        case .metal:    return "Калибровка фона"
        case .liveWire: return "Калибровка не требуется"
        }
    }
}

#Preview {
    ContentView()
}
