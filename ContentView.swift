import SwiftUI

// Главный экран приложения "Metal & Wire Detector"
struct ContentView: View {

    // Менеджер магнитометра — источник данных
    @StateObject private var magnetometer = MagnetometerManager()

    // Фаза жизненного цикла сцены — для остановки датчика в фоне
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            // Тёмный фон для лучшей читаемости
            Color.black.edgesIgnoringSafeArea(.all)

            VStack(spacing: 20) {
                // Заголовок
                Text("Metal & Wire Detector")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.top, 40)

                // Переключатель режимов работы
                modePicker

                // Подсказка о низкой точности датчика (если применимо)
                if magnetometer.isAvailable, let hint = magnetometer.accuracy.hintText {
                    accuracyHintBanner(text: hint)
                }

                Spacer()

                // Если датчик недоступен — показываем сообщение об ошибке
                if !magnetometer.isAvailable {
                    Text("Магнитометр недоступен\nна этом устройстве")
                        .font(.headline)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                } else {
                    // Круглый индикатор силы магнитного поля
                    detectorGauge

                    // Текстовый статус (зависит от уровня поля и режима)
                    statusText
                }

                Spacer()

                // Кнопка калибровки фона (актуальна для режима «Металл»)
                calibrationButton
                    .padding(.bottom, 40)
            }
            .padding(.horizontal, 20)
        }
        .onAppear {
            // Запуск опроса датчика при появлении экрана
            magnetometer.startUpdates()
        }
        .onDisappear {
            // Остановка при уходе с экрана (на случай навигации)
            magnetometer.stopUpdates()
        }
        .onChange(of: scenePhase) { phase in
            // Энергосбережение: датчик работает только когда приложение активно.
            // В фоне или при сворачивании опрос на 100 Гц быстро посадит батарею
            // и нагреет процессор — поэтому останавливаем.
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

    // MARK: - Баннер «низкая точность датчика»

    private func accuracyHintBanner(text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.yellow)
            Text(text)
                .font(.footnote)
                .foregroundColor(.white)
                .multilineTextAlignment(.leading)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(Color.yellow.opacity(0.15))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.yellow.opacity(0.5), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Текущее значение и шкала для активного режима

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
                Text(String(format: "%.1f", currentValue))
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
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

    // Калибровка имеет смысл только в режиме «Металл» и при нормальной точности
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
