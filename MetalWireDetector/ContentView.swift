import SwiftUI

// Главный экран приложения "Metal & Wire Detector"
struct ContentView: View {

    // Менеджер магнитометра - источник данных для UI
    @StateObject private var manager = MagnetometerManager()

    // Максимальное значение шкалы (μT). Всё, что выше - заполняет круг полностью.
    private let maxValue: Double = 200.0

    var body: some View {
        ZStack {
            // Фоновый градиент
            LinearGradient(
                colors: [Color(red: 0.05, green: 0.05, blue: 0.15),
                         Color(red: 0.1, green: 0.1, blue: 0.25)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 30) {
                // Заголовок приложения
                Text("Metal & Wire Detector")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.top, 40)

                Spacer()

                // Если магнитометр недоступен - показываем сообщение об ошибке
                if !manager.isAvailable {
                    errorView
                } else {
                    // Основной круглый индикатор
                    detectorCircle
                    // Текстовый статус под кругом
                    statusText
                }

                Spacer()

                // Кнопка калибровки
                calibrationButton
                    .padding(.bottom, 40)
            }
            .padding()
        }
    }

    // MARK: - Подвиды

    // Круглый индикатор силы магнитного поля
    private var detectorCircle: some View {
        ZStack {
            // Фоновый круг (бледный)
            Circle()
                .stroke(Color.white.opacity(0.15), lineWidth: 20)

            // Прогресс-круг, заполняется по мере увеличения значения
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    AngularGradient(
                        colors: [.green, .yellow, .orange, .red],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 20, lineCap: .round)
                )
                .rotationEffect(.degrees(-90)) // Начинаем заполнение сверху
                .animation(.easeInOut(duration: 0.2), value: progress)

            // Текстовое значение в центре круга
            VStack(spacing: 4) {
                Text(String(format: "%.1f", manager.magneticField))
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .contentTransition(.numericText())

                Text("μT")
                    .font(.title3)
                    .foregroundColor(.white.opacity(0.7))
            }
        }
        .frame(width: 280, height: 280)
    }

    // Текстовое сообщение о состоянии
    private var statusText: some View {
        Text(statusMessage)
            .font(.title3)
            .fontWeight(.semibold)
            .foregroundColor(statusColor)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
            .animation(.easeInOut, value: manager.magneticField)
    }

    // Кнопка калибровки
    private var calibrationButton: some View {
        Button(action: {
            // Тактильный отклик при нажатии кнопки
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            manager.calibrate()
        }) {
            HStack {
                Image(systemName: "scope")
                Text("Калибровка")
                    .fontWeight(.semibold)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.blue.opacity(0.8))
            )
        }
        .padding(.horizontal, 40)
    }

    // Сообщение об ошибке (если датчик недоступен)
    private var errorView: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 60))
                .foregroundColor(.yellow)
            Text(manager.errorMessage ?? "Ошибка датчика")
                .font(.headline)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
    }

    // MARK: - Вычисляемые свойства

    // Прогресс заполнения круга (от 0 до 1)
    private var progress: CGFloat {
        let value = min(manager.magneticField / maxValue, 1.0)
        return CGFloat(value)
    }

    // Статусное сообщение в зависимости от значения поля
    private var statusMessage: String {
        switch manager.magneticField {
        case ..<70:
            return "Стена чиста / Металл не обнаружен"
        case 70..<120:
            return "Подозрение на металл/проводку"
        default:
            return "ВНИМАНИЕ! Обнаружен металл или кабель!"
        }
    }

    // Цвет статусного текста в зависимости от значения поля
    private var statusColor: Color {
        switch manager.magneticField {
        case ..<70:
            return .green
        case 70..<120:
            return .yellow
        default:
            return .red
        }
    }
}

#Preview {
    ContentView()
}
