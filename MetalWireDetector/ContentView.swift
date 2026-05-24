//
//  ContentView.swift
//  MetalWireDetector
//
//  Главный экран приложения: круговой индикатор силы магнитного поля,
//  текущее значение в µT, статусная строка и кнопка калибровки.
//

import SwiftUI

struct ContentView: View {

    // MARK: - Состояние

    /// Менеджер магнитометра — источник всех данных для UI.
    @StateObject private var magnetometer = MagnetometerManager()

    /// Максимальное значение шкалы (в микротеслах).
    /// Свыше 200 µT прогресс считается "полным".
    private let maxScale: Double = 200.0

    // MARK: - Тело View

    var body: some View {
        ZStack {
            // Фон с мягким градиентом для приятного вида.
            LinearGradient(
                colors: [Color(.systemGray6), Color(.systemBackground)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 40) {

                // Заголовок приложения.
                Text("Metal & Wire Detector")
                    .font(.title2.bold())
                    .foregroundColor(.primary)
                    .padding(.top, 20)

                Spacer()

                // Круговой индикатор силы магнитного поля.
                CircularGauge(
                    value: magnetometer.magneticField,
                    maxValue: maxScale,
                    color: magnetometer.statusColor
                )
                .frame(width: 260, height: 260)

                // Текстовый статус — меняется по цвету и содержанию.
                Text(magnetometer.statusText)
                    .font(.headline)
                    .foregroundColor(magnetometer.statusColor)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                Spacer()

                // Кнопка калибровки — сбрасывает фоновое значение.
                Button(action: {
                    magnetometer.calibrate()
                }) {
                    HStack {
                        Image(systemName: "scope")
                        Text("Калибровка")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(14)
                }
                .padding(.horizontal, 30)
                .padding(.bottom, 30)
                // Если датчик недоступен — отключаем кнопку.
                .disabled(!magnetometer.isAvailable)
                .opacity(magnetometer.isAvailable ? 1.0 : 0.5)
            }
        }
    }
}

// MARK: - Кастомный круговой индикатор

/// Круглый прогресс-индикатор, заполняющийся от 0 до 100% в зависимости
/// от текущего значения относительно maxValue. В центре отображается
/// числовое значение поля в микротеслах.
struct CircularGauge: View {

    let value: Double
    let maxValue: Double
    let color: Color

    /// Доля заполнения шкалы (0.0…1.0).
    private var progress: Double {
        min(max(value / maxValue, 0.0), 1.0)
    }

    var body: some View {
        ZStack {
            // Фоновое (серое) кольцо шкалы.
            Circle()
                .stroke(
                    Color.gray.opacity(0.2),
                    style: StrokeStyle(lineWidth: 20, lineCap: .round)
                )

            // Активное кольцо прогресса — цвет зависит от уровня поля.
            Circle()
                .trim(from: 0, to: CGFloat(progress))
                .stroke(
                    color,
                    style: StrokeStyle(lineWidth: 20, lineCap: .round)
                )
                // Начинаем рисовать сверху (с 12 часов).
                .rotationEffect(.degrees(-90))
                // Плавная анимация при изменении значения.
                .animation(.easeInOut(duration: 0.25), value: progress)

            // Центральный блок: численное значение и единицы измерения.
            VStack(spacing: 4) {
                Text(String(format: "%.1f", value))
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                    .monospacedDigit()

                Text("µT")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Превью для Xcode Canvas

#Preview {
    ContentView()
}
