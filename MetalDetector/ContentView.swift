//
//  ContentView.swift
//  Metal & Wire Detector
//
//  Главный экран приложения.
//  Показывает:
//    - круглый индикатор силы магнитного поля;
//    - текстовый статус (зелёный/жёлтый/красный);
//    - кнопку калибровки;
//    - предупреждение, если магнитометр недоступен.
//

import SwiftUI

struct ContentView: View {

    // MARK: - Зависимости

    /// Менеджер магнитометра. @StateObject — потому что view владеет жизненным циклом объекта.
    @StateObject private var manager = MagnetometerManager()

    // MARK: - Тело view

    var body: some View {
        ZStack {
            // Фон — мягкий градиент для приятного визуального восприятия.
            LinearGradient(
                colors: [Color(.systemBackground), Color(.secondarySystemBackground)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 32) {

                // Заголовок приложения.
                VStack(spacing: 4) {
                    Text("Metal & Wire Detector")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                    Text("Детектор металла и проводки")
                        .font(.system(size: 14, weight: .regular, design: .rounded))
                        .foregroundColor(.secondary)
                }
                .padding(.top, 16)

                Spacer(minLength: 0)

                // Если датчик недоступен — показываем понятное сообщение вместо индикатора.
                if !manager.isAvailable {
                    unavailableView
                } else {
                    // Круглый индикатор силы поля. Цвет берём из текущего статуса.
                    CircularGaugeView(
                        value: manager.fieldStrength,
                        tintColor: statusColor(for: manager.fieldStrength)
                    )
                    .frame(maxWidth: 320)

                    // Статусная подпись под индикатором.
                    Text(statusText(for: manager.fieldStrength))
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundColor(statusColor(for: manager.fieldStrength))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .animation(.easeInOut(duration: 0.2), value: manager.fieldStrength)
                }

                Spacer(minLength: 0)

                // Кнопка калибровки — запоминает текущий фон, чтобы вычитать его из последующих замеров.
                Button(action: {
                    manager.calibrate()
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "scope")
                        Text("Калибровка")
                            .fontWeight(.semibold)
                    }
                    .font(.system(size: 18, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity)
                    .background(
                        // Делаем кнопку неактивной (приглушённой), если датчик недоступен.
                        manager.isAvailable ? Color.accentColor : Color.gray
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: .black.opacity(0.1), radius: 6, x: 0, y: 3)
                }
                .padding(.horizontal, 24)
                .disabled(!manager.isAvailable)

                // Подсказка под кнопкой — для прозрачности UX.
                Text("Прижмите телефон к чистой поверхности и нажмите «Калибровка», чтобы компенсировать фон.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 16)
            }
        }
        // Запускаем датчик при появлении экрана и останавливаем при исчезновении —
        // это экономит батарею и корректно с точки зрения жизненного цикла.
        .onAppear {
            manager.start()
        }
        .onDisappear {
            manager.stop()
        }
    }

    // MARK: - Вспомогательные view

    /// Сообщение, когда магнитометр недоступен на устройстве (например, симулятор или старая железка).
    private var unavailableView: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 64))
                .foregroundColor(.orange)
            Text("Магнитометр недоступен")
                .font(.system(size: 22, weight: .semibold, design: .rounded))
            Text("На этом устройстве отсутствует датчик магнитного поля или он недоступен приложению.")
                .font(.system(size: 15))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    // MARK: - Бизнес-логика статуса

    /// Текст статуса в зависимости от текущей силы поля.
    /// Пороговые значения соответствуют требованиям задачи.
    private func statusText(for value: Double) -> String {
        switch value {
        case ..<70:
            return "Стена чиста / Металл не обнаружен"
        case 70..<120:
            return "Подозрение на металл/проводку"
        default:
            return "ВНИМАНИЕ! Обнаружен металл или кабель!"
        }
    }

    /// Цвет статуса в зависимости от текущей силы поля.
    private func statusColor(for value: Double) -> Color {
        switch value {
        case ..<70:
            return .green
        case 70..<120:
            return .yellow
        default:
            return .red
        }
    }
}

// MARK: - Превью для Xcode Canvas

#Preview {
    ContentView()
}
