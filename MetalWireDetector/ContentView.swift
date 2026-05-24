//
//  ContentView.swift
//  Metal & Wire Detector
//
//  Главный экран приложения: круглый индикатор силы магнитного поля,
//  текстовый статус и кнопка калибровки.
//

import SwiftUI

/// Перечисление статусов уровня магнитного поля.
/// Удобно использовать вместо «магических» чисел напрямую в View.
enum DetectionStatus {
    case clean          // Поле в норме — металл не обнаружен
    case suspicious     // Поле слегка повышено — возможно металл/проводка
    case detected       // Поле сильно повышено — точно металл/кабель

    /// Текстовое описание статуса на русском языке.
    var title: String {
        switch self {
        case .clean:
            return "Стена чиста / Металл не обнаружен"
        case .suspicious:
            return "Подозрение на металл/проводку"
        case .detected:
            return "ВНИМАНИЕ! Обнаружен металл или кабель!"
        }
    }

    /// Цвет, в котором следует отображать статус и индикатор.
    var color: Color {
        switch self {
        case .clean:      return .green
        case .suspicious: return .yellow
        case .detected:   return .red
        }
    }

    /// Системная иконка SF Symbols для каждого статуса.
    var iconName: String {
        switch self {
        case .clean:      return "checkmark.shield.fill"
        case .suspicious: return "exclamationmark.triangle.fill"
        case .detected:   return "bolt.trianglebadge.exclamationmark.fill"
        }
    }

    /// Возвращает статус, исходя из значения поля в микротеслах.
    /// Согласно ТЗ:
    ///   - до 70 μT      → «чисто»
    ///   - 70…120 μT     → «подозрение»
    ///   - выше 120 μT   → «обнаружено»
    static func from(value: Double) -> DetectionStatus {
        switch value {
        case ..<70:        return .clean
        case 70..<120:     return .suspicious
        default:           return .detected
        }
    }
}

/// Главный экран приложения.
struct ContentView: View {

    // MARK: - Состояние

    /// Менеджер магнитометра — источник всех данных на экране.
    /// `@StateObject`, потому что он создаётся и живёт вместе с этим View.
    @StateObject private var manager = MagnetometerManager()

    /// Максимальное значение шкалы индикатора.
    /// 200 μT — комфортный потолок, при котором стрелка успевает реагировать.
    private let gaugeMax: Double = 200.0

    // MARK: - Вспомогательные свойства

    /// Текущий статус, вычисляемый из значения поля.
    private var status: DetectionStatus {
        DetectionStatus.from(value: manager.magneticFieldStrength)
    }

    // MARK: - Тело view

    var body: some View {
        ZStack {
            // Тёмный фон, на котором цвета индикатора смотрятся выразительнее.
            backgroundGradient
                .ignoresSafeArea()

            VStack(spacing: 28) {

                // Заголовок приложения.
                headerView

                Spacer(minLength: 8)

                // Если магнитометр недоступен — показываем сообщение.
                if !manager.isSensorAvailable {
                    sensorUnavailableView
                } else {
                    // Круглый индикатор.
                    CircularGauge(
                        value: manager.magneticFieldStrength,
                        maxValue: gaugeMax,
                        accentColor: status.color
                    )
                    .padding(.horizontal, 32)

                    // Текстовый статус под индикатором.
                    statusView
                }

                Spacer()

                // Кнопка калибровки внизу экрана.
                calibrationButton
                    .padding(.bottom, 24)
            }
            .padding(.horizontal)
        }
        // Запускаем поток данных при появлении экрана…
        .onAppear {
            manager.startUpdates()
        }
        // …и останавливаем при уходе с экрана, чтобы не тратить батарею.
        .onDisappear {
            manager.stopUpdates()
        }
        // Показываем алерт при ошибке от датчика.
        .alert(
            "Ошибка датчика",
            isPresented: .constant(manager.errorMessage != nil),
            actions: {
                Button("OK", role: .cancel) {
                    manager.errorMessage = nil
                }
            },
            message: {
                Text(manager.errorMessage ?? "")
            }
        )
    }

    // MARK: - Подвиды

    /// Градиентный фон.
    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color(red: 0.06, green: 0.07, blue: 0.10),
                Color(red: 0.12, green: 0.13, blue: 0.18)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// Заголовок и подпись над индикатором.
    private var headerView: some View {
        VStack(spacing: 4) {
            Text("Metal & Wire Detector")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            Text("Детектор металла и проводки")
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .foregroundColor(.white.opacity(0.6))
        }
        .padding(.top, 16)
    }

    /// Сообщение, когда датчик недоступен.
    private var sensorUnavailableView: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 64))
                .foregroundColor(.orange)

            Text("Магнитометр недоступен")
                .font(.title2)
                .foregroundColor(.white)

            Text("Запустите приложение на реальном устройстве iPhone, " +
                 "оснащённом магнитометром.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.white.opacity(0.7))
                .padding(.horizontal, 24)
        }
    }

    /// Карточка с текстовым статусом текущего уровня поля.
    private var statusView: some View {
        HStack(spacing: 12) {
            Image(systemName: status.iconName)
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(status.color)

            Text(status.title)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundColor(status.color)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(status.color.opacity(0.5), lineWidth: 1)
        )
        .padding(.horizontal, 24)
        // Плавный переход цвета при смене статуса.
        .animation(.easeInOut(duration: 0.25), value: status.color)
    }

    /// Кнопка калибровки — обнуляет фоновое значение поля.
    private var calibrationButton: some View {
        Button(action: {
            manager.calibrate()
        }) {
            HStack(spacing: 10) {
                Image(systemName: "scope")
                    .font(.system(size: 18, weight: .semibold))
                Text(manager.isCalibrated ? "Калибровать заново" : "Калибровка")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
            }
            .foregroundColor(.white)
            .padding(.vertical, 14)
            .padding(.horizontal, 32)
            .background(
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color.blue, Color.purple],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            )
            .shadow(color: .black.opacity(0.3), radius: 6, x: 0, y: 3)
        }
        // Если датчик недоступен — отключаем кнопку калибровки.
        .disabled(!manager.isSensorAvailable)
        .opacity(manager.isSensorAvailable ? 1.0 : 0.5)
    }
}

// MARK: - Превью для Xcode

#if DEBUG
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
#endif
