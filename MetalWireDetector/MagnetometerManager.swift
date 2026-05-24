import Foundation
import CoreMotion
import Combine
import UIKit

// Класс-наблюдатель за магнитометром.
// Считывает данные с датчика, вычисляет суммарную силу магнитного поля
// и публикует её для SwiftUI-вьюшек через @Published свойство.
final class MagnetometerManager: ObservableObject {

    // Текущее значение магнитного поля в микротеслах (μT) с учётом калибровки
    @Published var magneticField: Double = 0.0

    // Флаг доступности датчика (для отображения ошибки в UI, если магнитометра нет)
    @Published var isAvailable: Bool = true

    // Сообщение об ошибке (если датчик недоступен)
    @Published var errorMessage: String? = nil

    // Менеджер CoreMotion
    private let motionManager = CMMotionManager()

    // Очередь для обработки данных датчика
    private let queue = OperationQueue()

    // Калибровочное смещение - значение фонового поля, которое вычитается из измерений
    private var calibrationOffset: Double = 0.0

    // Генератор тактильной отдачи (вибрации) при превышении порога
    private let hapticGenerator = UIImpactFeedbackGenerator(style: .heavy)

    // Порог, после которого включается вибрация (в μT)
    private let hapticThreshold: Double = 100.0

    // Время последней вибрации - чтобы не вибрировать слишком часто
    private var lastHapticTime: Date = .distantPast

    // Минимальный интервал между вибрациями (в секундах)
    private let hapticInterval: TimeInterval = 0.5

    init() {
        startUpdates()
    }

    deinit {
        stopUpdates()
    }

    // Запуск считывания данных с магнитометра
    func startUpdates() {
        // Проверяем доступность магнитометра на устройстве
        guard motionManager.isMagnetometerAvailable else {
            isAvailable = false
            errorMessage = "Магнитометр недоступен на этом устройстве"
            return
        }

        // Частота обновления данных - 10 раз в секунду
        motionManager.magnetometerUpdateInterval = 0.1

        // Подготавливаем генератор вибрации для уменьшения задержки
        hapticGenerator.prepare()

        // Запускаем обновления магнитометра
        motionManager.startMagnetometerUpdates(to: queue) { [weak self] data, error in
            guard let self = self else { return }

            // Обработка ошибки получения данных
            if let error = error {
                DispatchQueue.main.async {
                    self.errorMessage = "Ошибка датчика: \(error.localizedDescription)"
                }
                return
            }

            // Получаем данные магнитного поля
            guard let field = data?.magneticField else { return }

            // Считаем общую силу магнитного поля как длину вектора (x, y, z)
            let magnitude = sqrt(field.x * field.x + field.y * field.y + field.z * field.z)

            // Применяем калибровку - вычитаем фоновое значение
            // abs(), чтобы не уходить в отрицательные значения при калибровке выше текущего фона
            let calibratedValue = max(0.0, magnitude - self.calibrationOffset)

            // Обновляем UI в главной очереди
            DispatchQueue.main.async {
                self.magneticField = calibratedValue
                self.triggerHapticIfNeeded(for: calibratedValue)
            }
        }
    }

    // Остановка считывания данных
    func stopUpdates() {
        if motionManager.isMagnetometerActive {
            motionManager.stopMagnetometerUpdates()
        }
    }

    // Калибровка - запоминает текущее значение как фоновое
    func calibrate() {
        // Прибавляем текущее значение к существующему смещению,
        // т.к. magneticField уже отображает значение с учётом предыдущей калибровки
        calibrationOffset += magneticField
        magneticField = 0.0
    }

    // Сброс калибровки в исходное состояние
    func resetCalibration() {
        calibrationOffset = 0.0
    }

    // Активация тактильной отдачи при превышении порога
    private func triggerHapticIfNeeded(for value: Double) {
        guard value > hapticThreshold else { return }

        // Ограничиваем частоту вибраций
        let now = Date()
        guard now.timeIntervalSince(lastHapticTime) >= hapticInterval else { return }

        lastHapticTime = now
        hapticGenerator.impactOccurred()
        // Готовим генератор к следующему срабатыванию
        hapticGenerator.prepare()
    }
}
