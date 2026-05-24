import Foundation
import CoreMotion
import Combine
import UIKit

// Менеджер магнитометра — отвечает за получение данных с датчика,
// расчёт силы магнитного поля, калибровку и тактильную отдачу.
final class MagnetometerManager: ObservableObject {

    // Текущая сила магнитного поля (микротесла), с учётом калибровки
    @Published var magneticFieldStrength: Double = 0.0

    // Признак того, что датчик недоступен (для отображения ошибки в UI)
    @Published var isAvailable: Bool = true

    // Сохранённое фоновое значение (применяется при калибровке)
    private var calibrationOffset: Double = 0.0

    // Менеджер движения из CoreMotion
    private let motionManager = CMMotionManager()

    // Очередь для обработки данных от датчика
    private let motionQueue = OperationQueue()

    // Генератор тактильной отдачи (вибрация при превышении порога)
    private let hapticGenerator = UIImpactFeedbackGenerator(style: .heavy)

    // Флаг для предотвращения слишком частой вибрации
    private var lastHapticTime: Date = .distantPast

    // Порог срабатывания вибрации (микротесла)
    private let hapticThreshold: Double = 100.0

    init() {
        // Проверка доступности магнитометра на устройстве
        guard motionManager.isMagnetometerAvailable else {
            self.isAvailable = false
            return
        }

        // Период опроса датчика — 10 раз в секунду
        motionManager.magnetometerUpdateInterval = 0.1

        // Предварительная подготовка генератора вибрации (снижает задержку)
        hapticGenerator.prepare()
    }

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

            // Применение калибровочного смещения (не уходим ниже нуля)
            let calibrated = max(0.0, rawMagnitude - self.calibrationOffset)

            // Обновление публикуемого значения в главном потоке (для UI)
            DispatchQueue.main.async {
                self.magneticFieldStrength = calibrated
                self.triggerHapticIfNeeded(for: calibrated)
            }
        }
    }

    // Остановка считывания
    func stopUpdates() {
        if motionManager.isMagnetometerActive {
            motionManager.stopMagnetometerUpdates()
        }
    }

    // Калибровка — запомнить текущее значение как фоновое
    func calibrate() {
        // Получаем «сырое» значение в момент калибровки
        // (текущее опубликованное значение + ранее сохранённый офсет)
        let currentRaw = magneticFieldStrength + calibrationOffset
        calibrationOffset = currentRaw

        // Сразу обнуляем показания, чтобы UI отреагировал немедленно
        DispatchQueue.main.async {
            self.magneticFieldStrength = 0.0
        }
    }

    // Сброс калибровки (если потребуется)
    func resetCalibration() {
        calibrationOffset = 0.0
    }

    // Вибрация при превышении порога с защитой от частого срабатывания
    private func triggerHapticIfNeeded(for value: Double) {
        guard value > hapticThreshold else { return }

        // Не чаще одной вибрации в 0.3 секунды
        let now = Date()
        if now.timeIntervalSince(lastHapticTime) > 0.3 {
            hapticGenerator.impactOccurred()
            hapticGenerator.prepare()
            lastHapticTime = now
        }
    }
}
