//
//  CircularGaugeView.swift
//  Metal & Wire Detector
//
//  Кастомный круглый индикатор, заполняющийся пропорционально силе магнитного поля.
//  Диапазон: 0...maxValue (по умолчанию 200 μT).
//  В центре круга отображается текущее значение крупным шрифтом.
//

import SwiftUI

struct CircularGaugeView: View {

    // MARK: - Входные параметры

    /// Текущее значение в μT.
    let value: Double

    /// Максимальное значение шкалы (после него круг считается полностью заполненным).
    var maxValue: Double = 200.0

    /// Цвет заполнения дуги — задаётся снаружи, чтобы соответствовать статусу
    /// (зелёный/жёлтый/красный).
    let tintColor: Color

    // MARK: - Вычисляемые свойства

    /// Прогресс от 0.0 до 1.0, ограниченный сверху, чтобы дуга не "перекручивалась".
    private var progress: Double {
        guard maxValue > 0 else { return 0 }
        return min(max(value / maxValue, 0.0), 1.0)
    }

    // MARK: - Тело view

    var body: some View {
        ZStack {
            // Фоновое кольцо — серая "канва", по которой нарисована дуга прогресса.
            Circle()
                .stroke(
                    Color.gray.opacity(0.25),
                    style: StrokeStyle(lineWidth: 20, lineCap: .round)
                )

            // Дуга прогресса — рисуется поверх фонового кольца.
            Circle()
                .trim(from: 0, to: CGFloat(progress))
                .stroke(
                    // Градиент делает индикатор "живым" и визуально приятным.
                    AngularGradient(
                        gradient: Gradient(colors: [tintColor.opacity(0.6), tintColor]),
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 20, lineCap: .round)
                )
                // Поворачиваем, чтобы дуга начиналась сверху (12 часов).
                .rotationEffect(.degrees(-90))
                // Плавная анимация изменения значения.
                .animation(.easeInOut(duration: 0.25), value: progress)

            // Центральная часть — числовое значение и единицы измерения.
            VStack(spacing: 4) {
                // Крупное число — текущее значение μT, округлённое до целого.
                Text("\(Int(value.rounded()))")
                    .font(.system(size: 72, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                    .monospacedDigit()
                    // contentTransition даёт красивый "числовой" анимированный переход на iOS 16+.
                    .contentTransition(.numericText())

                // Подпись единиц измерения.
                Text("μT")
                    .font(.system(size: 22, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
            }
        }
        // Делаем элемент квадратным — круг будет круглым.
        .aspectRatio(1, contentMode: .fit)
        .padding(8)
    }
}

// MARK: - Превью для Xcode Canvas

#Preview {
    CircularGaugeView(value: 85, tintColor: .yellow)
        .frame(width: 280, height: 280)
        .padding()
}
