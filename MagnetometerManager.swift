import Foundation
import CoreMotion
import Combine
import UIKit

// Режим работы детектора
enum DetectorMode: String, CaseIterable, Identifiable {
    case metal       // Поиск металла — статическое (постоянное) магнитное поле
    case liveWire    // Поиск проводов под напряжением — переменное поле 50/60 Гц

    var id: String { rawValue }

    var title: String {
        switch self {
        case .metal:    return "Металл"
        case .liveWire: return "Провод 220В"
        }
    }
}

// Менеджер магнитометра — отвечает за получение данных с датчика,
// расчёт силы магнитного поля (постоянной и переменной составляющих),
// калибровку и тактильную отдачу.
final class MagnetometerManager: ObservableObject {

    // MARK: - Публикуемые свойства (для UI)

    // Текущая сила магнитного поля (μT), с учётом калибровки — для режима «Металл»
    @Published var magneticFieldStrength: Double = 0.0

    // Амплитуда переменной составляющей поля (μT) — для режима «Провод 220В».
    // Рассчитывается как стандартное отклонение скользящего окна × √2.
    @Published var acAmplitude: Double = 0.0

    // Текущий режим работы
    @Published var mode: DetectorMode = .metal

    // Признак того, что датчик недоступен (для отображения ошибки в UI)
    @Published var isAvailable: Bool = true

    // MARK: - Внутреннее состояние

    // Сохранённое фоновое значение постоянной составляющей (калибровка)
    private var calibrationOffset: Double = 0.0

    // Скользящее окно последних замеров — для расчёта AC-амплитуды
    private var sampleWindow: [Double] = []
    private let windowSize = 60   // ≈ 0.6 секунды при частоте 100 Гц — достаточно для оценки колебаний

    // Менеджер движения из CoreMotion
    private let motionManager = CMMotionManager()

    // Очередь для обработки данных от датчика
    private let motionQueue = OperationQueue()

    // Генератор тактильной отдачи (вибрация при превышении порога)
    private let hapticGenerator = UIImpactFeedbackGenerator(style: .heavy)

    // Флаг для предотвращения слишком частой вибрации
    private var lastHapticTime: Date = .distantPast

    // Пороги срабатывания вибрации для каждого режима (μT)
    private let metalHapticThreshold: Double = 100.0
    private let wireHapticThreshold: Double = 3.0

    // MARK: - Инициализация

    init() {
        // Проверка доступности магнитометра на устройстве
        guard motionManager.isMagnetometerAvailable else {
            self.isAvailable = false
            return
        }

        // Высокая частота опроса — 100 Гц, чтобы уловить колебания 50/60 Гц
        // (по Найквисту это пограничный случай, но выраженный alias заметен).
        motionManager.magnetometerUpdateInterval = 0.01

        // Предварительная подготовка генератора вибрации (снижает задержку)
        hapticGenerator.prepare()
    }

    // MARK: - Управление обновлениями

    // Запуск считывания данных с магнитометра
    func startUpdates() {
        guard motionManager.isMagnetometerAvailable else {
            self.isAvailable = false
            return
        }

        motionManager.startMagnetometerUpdates(to: motionQueue) { [weak self] data, error in
            guard let self = self, let field = data?.magneticField, error == nil else { return }

            // Расчёт общей силы магнитного поля по формуле вектора
            let rawMagnitude = sqrt(field.x * field.x + field.y * field.y + field.z * field.z)

            // Добавляем в скользящее окно и подрезаем до размера
            self.sampleWindow.append(rawMagnitude)
            if self.sampleWindow.count > self.windowSize {
                self.sampleWindow.removeFirst(self.sampleWindow.count - self.windowSize)
            }

            // Постоянная составляющая (DC) — для режима «Металл»
            let dcCalibrated = max(0.0, rawMagnitude - self.calibrationOffset)

            // Переменная составляющая (AC) — для режима «Провод 220В».
            // Если в окне ещё мало данных, считаем 0.
            let acValue = self.sampleWindow.count >= 10
                ? self.computeAcAmplitude(samples: self.sampleWindow)
                : 0.0

            // Обновление публикуемых значений в главном потоке (для UI)
            DispatchQueue.main.async {
                self.magneticFieldStrength = dcCalibrated
                self.acAmplitude = acValue
                self.triggerHapticIfNeeded(dc: dcCalibrated, ac: acValue)
            }
        }
    }

    // Остановка считывания
    func stopUpdates() {
        if motionManager.isMagnetometerActive {
            motionManager.stopMagnetometerUpdates()
        }
    }

    // MARK: - Калибровка

    // Калибровка — запомнить текущее значение как фоновое (только для DC).
    // Для AC-режима калибровка не нужна: переменная составляющая по природе
    // около нуля при отсутствии источника.
    func calibrate() {
        // Берём «сырое» значение в момент калибровки
        let currentRaw = magneticFieldStrength + calibrationOffset
        calibrationOffset = currentRaw

        DispatchQueue.main.async {
            self.magneticFieldStrength = 0.0
        }
    }

    // Сброс калибровки
    func resetCalibration() {
        calibrationOffset = 0.0
    }

    // MARK: - Расчёт AC-амплитуды

    // Стандартное отклонение окна × √2 ≈ амплитуда синусоиды.
    // У постоянного поля разброс маленький → AC ≈ 0.
    // У переменного поля (рядом с проводом 220В) разброс растёт.
    private func computeAcAmplitude(samples: [Double]) -> Double {
        let n = Double(samples.count)
        let mean = samples.reduce(0, +) / n
        let variance = samples.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / n
        let stdDev = sqrt(variance)
        return stdDev * sqrt(2.0)
    }

    // MARK: - Тактильная отдача

    // Вибрация при превышении порога — пороги разные для каждого режима.
    private func triggerHapticIfNeeded(dc: Double, ac: Double) {
        let exceeded: Bool
        switch mode {
        case .metal:
            exceeded = dc > metalHapticThreshold
        case .liveWire:
            exceeded = ac > wireHapticThreshold
        }
        guard exceeded else { return }

        // Не чаще одной вибрации в 0.3 секунды
        let now = Date()
        if now.timeIntervalSince(lastHapticTime) > 0.3 {
            hapticGenerator.impactOccurred()
            hapticGenerator.prepare()
            lastHapticTime = now
        }
    }
}
