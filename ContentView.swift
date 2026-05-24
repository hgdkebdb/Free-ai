import SwiftUI

// Главный экран приложения "Metal & Wire Detector"
struct ContentView: View {

    // Менеджер магнитометра — источник данных
    @StateObject private var magnetometer = MagnetometerManager()

    // Максимальное значение шкалы (микротесла)
    private let maxFieldValue: Double = 200.0

    var body: some View {
        ZStack {
            // Тёмный фон для лучшей читаемости
            Color.black.edgesIgnoringSafeArea(.all)

            VStack(spacing: 30) {
                // Заголовок
                Text("Metal & Wire Detector")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.top, 40)

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

                    // Текстовый статус (зависит от уровня поля)
                    statusText
                }

                Spacer()

                // Кнопка калибровки
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

    // MARK: - Круглый индикатор

    private var detectorGauge: some View {
        ZStack {
            // Фоновый круг
            Circle()
                .stroke(Color.gray.opacity(0.3), lineWidth: 20)

            // Заполняющийся круг — отражает текущую силу поля
            Circle()
                .trim(from: 0.0, to: CGFloat(min(magnetometer.magneticFieldStrength / maxFieldValue, 1.0)))
                .stroke(
                    gaugeColor,
                    style: StrokeStyle(lineWidth: 20, lineCap: .round)
                )
                .rotationEffect(.degrees(-90)) // Старт сверху
                .animation(.easeInOut(duration: 0.2), value: magnetometer.magneticFieldStrength)

            // Значение в центре круга
            VStack(spacing: 4) {
                Text(String(format: "%.1f", magnetometer.magneticFieldStrength))
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text("μT")
                    .font(.title3)
                    .foregroundColor(.gray)
            }
        }
        .frame(width: 260, height: 260)
    }

    // MARK: - Цвет шкалы в зависимости от уровня поля

    private var gaugeColor: Color {
        let value = magnetometer.magneticFieldStrength
        switch value {
        case ..<70:
            return .green
        case 70..<120:
            return .yellow
        default:
            return .red
        }
    }

    // MARK: - Текстовый статус

    private var statusText: some View {
        let value = magnetometer.magneticFieldStrength
        let (text, color): (String, Color)

        // Определяем текст и цвет по диапазонам, заданным в ТЗ
        switch value {
        case ..<70:
            text = "Стена чиста / Металл не обнаружен"
            color = .green
        case 70..<120:
            text = "Подозрение на металл/проводку"
            color = .yellow
        default:
            text = "ВНИМАНИЕ! Обнаружен металл или кабель!"
            color = .red
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
                Text("Калибровка")
                    .fontWeight(.semibold)
            }
            .foregroundColor(.white)
            .padding(.vertical, 14)
            .padding(.horizontal, 40)
            .background(Color.blue)
            .clipShape(Capsule())
        }
        .disabled(!magnetometer.isAvailable)
    }
}

#Preview {
    ContentView()
}
