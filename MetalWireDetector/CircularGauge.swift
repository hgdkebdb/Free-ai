//
//  CircularGauge.swift
//  Metal & Wire Detector
//
//  Кастомный круглый индикатор силы магнитного поля.
//  Принимает текущее значение в μT и максимум шкалы,
//  отображает заполненную дугу + центральное значение.
//

import SwiftUI

/// Круговой индикатор, который заполняется в зависимости от значения.
struct CircularGauge: View {

    // MARK: - Входные параметры

    /// Текущее значение магнитного поля в микротеслах.
    let value: Double

    /// Максимальное значение шкалы (по ТЗ — 200+ μT).
    let maxValue: Double

    /// Цвет заполнения (мы передаём его из ContentView в зависимости от уровня).
    let accentColor: Color

    // MARK: - Вспомогательные вычисления

    /// Доля заполнения круга от 0.0 до 1.0.
    /// Ограничиваем сверху, чтобы дуга не «переезжала» при значениях > maxValue.
    private var progress: Double {
        guard maxValue > 0 else { return 0 }
        return min(max(value / maxValue, 0), 1)
    }

    // MARK: - Тело view

    var body: some View {
        ZStack {
            // 1) Фоновое серое кольцо — «недозаполненная» часть индикатора.
            Circle()
                .stroke(
                    Color.gray.opacity(0.25),
                    style: StrokeStyle(lineWidth: 22, lineCap: .round)
                )

            // 2) Цветная дуга, отображающая текущий уровень.
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [
                            accentColor.opacity(0.6),
                            accentColor
                        ]),
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 22, lineCap: .round)
                )
                // Поворачиваем, чтобы заполнение начиналось сверху (как у часов в 12).
                .rotationEffect(.degrees(-90))
                // Плавная анимация при изменении значения.
                .animation(.easeOut(duration: 0.25), value: progress)

            // 3) Центральная часть: число в μT и подпись единиц.
            VStack(spacing: 4) {
                Text(String(format: "%.1f", value))
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                    // Авто-уменьшение шрифта на маленьких экранах.
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)

                Text("μT")
                    .font(.system(size: 22, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 24)
        }
        // Фиксируем квадратное соотношение, чтобы круг оставался кругом.
        .aspectRatio(1, contentMode: .fit)
    }
}

// MARK: - Превью для Xcode

#if DEBUG
struct CircularGauge_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            CircularGauge(value: 45, maxValue: 200, accentColor: .green)
            CircularGauge(value: 95, maxValue: 200, accentColor: .yellow)
            CircularGauge(value: 160, maxValue: 200, accentColor: .red)
        }
        .padding()
    }
}
#endif
