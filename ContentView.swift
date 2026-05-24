import SwiftUI

// Главный экран приложения "Metal & Wire Detector"
struct ContentView: View {

    // Менеджер магнитометра — источник данных
    @StateObject private var magnetometer = MagnetometerManager()

    var body: some View {
        ZStack {
            // Тёмный фон для лучшей читаемости
            Color.black.edgesIgnoringSafeArea(.all)

            VStack(spacing: 24) {
                // Заголовок
                Text("Metal & Wire Detector")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.top, 40)

                // Переключатель режимов работы
                modePicker

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

                // Кнопка калибровки (актуальна только для режима «Металл»)
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
            // Остановка опроса при уходе с экрана (экономия батареи)
            magnetometer.stopUpdates()
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

    // MARK: - Текущее значение и шкала для активного режима

    // Значение, отображаемое в круге (зависит от режима)
    private var currentValue: Double {
        switch magnetometer.mode {
        case .metal:    return magnetometer.magneticFieldStrength
        case .liveWire: return magnetometer.acAmplitude
        }
    }

    // Максимум шкалы для нормирования круга
    private var maxScaleValue: Double {
        switch magnetometer.mode {
        case .metal:    return 200.0   // μT
        case .liveWire: return 10.0    // μT (амплитуда переменной составляющей)
        }
    }

    // Пороги (низкий / высокий) для смены цвета и текста
    private var thresholds: (low: Double, high: Double) {
        switch magnetometer.mode {
        case .metal:    return (70.0, 120.0)
        case .liveWire: return (1.0, 3.0)
        }
    }

    // MARK: - Круглый индикатор

    private var detectorGauge: some View {
        ZStack {
            // Фоновый круг
            Circle()
                .stroke(Color.gray.opacity(0.3), lineWidth: 20)

            // Заполняющийся круг — отражает текущую величину
            Circle()
                .trim(from: 0.0, to: CGFloat(min(currentValue / maxScaleValue, 1.0)))
                .stroke(
                    gaugeColor,
                    style: StrokeStyle(lineWidth: 20, lineCap: .round)
                )
                .rotationEffect(.degrees(-90)) // Старт сверху
                .animation(.easeInOut(duration: 0.2), value: currentValue)

            // Значение в центре круга
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

    // Подпись единиц — μT в обоих режимах, но в проводе это «амплитуда»
    private var unitLabel: String {
        switch magnetometer.mode {
        case .metal:    return "μT"
        case .liveWire: return "μT (AC)"
        }
    }

    // MARK: - Цвет шкалы в зависимости от уровня поля

    private var gaugeColor: Color {
        let (low, high) = thresholds
        switch currentValue {
        case ..<low:    return .green
        case low..<high: return .yellow
        default:        return .red
        }
    }

    // MARK: - Текстовый статус

    private var statusText: some View {
        let (low, high) = thresholds
        let value = currentValue
        let (text, color): (String, Color)

        // Определяем текст и цвет по диапазонам, заданным для текущего режима
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

    // MARK: - Кнопка калибровки

    private var calibrationButton: some View {
        Button(action: {
            // Сохраняем текущее значение как фон
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

    // Калибровка имеет смысл только в режиме «Металл»
    private var calibrationButtonEnabled: Bool {
        magnetometer.isAvailable && magnetometer.mode == .metal
    }

    private var calibrationButtonTitle: String {
        switch magnetometer.mode {
        case .metal:    return "Калибровка"
        case .liveWire: return "Калибровка не требуется"
        }
    }
}

#Preview {
    ContentView()
}
