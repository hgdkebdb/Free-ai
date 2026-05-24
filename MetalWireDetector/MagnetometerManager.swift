//
//  MagnetometerManager.swift
//  MetalWireDetector
//
//  Менеджер магнитометра: получает данные с датчика через CoreMotion,
//  вычисляет общую силу магнитного поля и публикует её для UI.
//

import Foundation
import CoreMotion
import UIKit
import Combine
import SwiftUI

/// Класс, отвечающий за работу с магнитометром устройства.
/// Использует CMMotionManager для непрерывного получения данных
/// и публикует текущее значение силы поля (в микротеслах).
final class MagnetometerManager: ObservableObject {

    // MARK: - Публикуемые свойства (для SwiftUI)

    /// Текущая сила магнитного поля с учётом калибровки (в µT).
    @Published var magneticField: Double = 0.0

    /// Текстовый статус, отображаемый под индикатором.
    @Published var statusText: String = "Поиск сигнала…"

    /// Цвет статуса (зависит от уровня поля).
    @Published var statusColor: Color = .gray

    /// Флаг доступности магнитометра на устройстве.
    @Published var isAvailable: Bool = true

    // MARK: - Приватные свойства

    /// Основной объект CoreMotion для работы с датчиками движения.
    private let motionManager = CMMotionManager()

    /// Очередь для обработки данных магнитометра.
    private let queue = OperationQueue()

    /// Значение фонового магнитного поля (запоминается при калибровке).
    /// По умолчанию равно 0, то есть калибровка не активна.
    private var calibrationOffset: Double = 0.0

    /// Генератор тактильной отдачи (вибрации).
    private let hapticGenerator = UIImpactFeedbackGenerator(style: .heavy)

    /// Защита от слишком частой вибрации — фиксируем время последнего хаптика.
    private var lastHapticTime: Date = .distantPast

    // MARK: - Константы

    /// Пороги уровней поля в микротеслах.
    private enum Thresholds {
        static let safe: Double = 70.0       // До 70 µT — норма
        static let suspicious: Double = 120.0 // 70–120 µT — подозрение
        static let hapticTrigger: Double = 100.0 // Порог для виброотклика
    }

    // MARK: - Инициализация

    init() {
        // Подготовим генератор вибрации заранее, чтобы реакция была мгновенной.
        hapticGenerator.prepare()
        startUpdates()
    }

    deinit {
        stopUpdates()
    }

    // MARK: - Публичные методы

    /// Запускает получение данных с магнитометра.
    func startUpdates() {
        // Проверяем, доступен ли магнитометр на данном устройстве.
        guard motionManager.isMagnetometerAvailable else {
            isAvailable = false
            statusText = "Магнитометр недоступен"
            statusColor = .gray
            return
        }

        // Интервал обновления — 10 раз в секунду (достаточно плавно для UI).
        motionManager.magnetometerUpdateInterval = 1.0 / 10.0

        // Запускаем обновления и обрабатываем каждый замер в замыкании.
        motionManager.startMagnetometerUpdates(to: queue) { [weak self] data, error in
            guard let self = self, let field = data?.magneticField, error == nil else { return }

            // Считаем модуль вектора магнитного поля по формуле sqrt(x² + y² + z²).
            let magnitude = sqrt(field.x * field.x + field.y * field.y + field.z * field.z)

            // Учитываем калибровочное смещение (фоновое значение).
            // Используем max(0, …), чтобы не получать отрицательные значения.
            let adjusted = max(0.0, magnitude - self.calibrationOffset)

            // Обновляем UI на главном потоке.
            DispatchQueue.main.async {
                self.magneticField = adjusted
                self.updateStatus(for: adjusted)
                self.triggerHapticIfNeeded(value: adjusted)
            }
        }
    }

    /// Останавливает получение данных с магнитометра.
    func stopUpdates() {
        if motionManager.isMagnetometerActive {
            motionManager.stopMagnetometerUpdates()
        }
    }

    /// Калибровка: запоминаем текущий сырой замер как фоновый уровень,
    /// чтобы последующие значения отображались относительно него.
    func calibrate() {
        guard let field = motionManager.magnetometerData?.magneticField else { return }
        let rawMagnitude = sqrt(field.x * field.x + field.y * field.y + field.z * field.z)
        calibrationOffset = rawMagnitude
    }

    /// Сброс калибровки (возврат к "сырым" показаниям).
    func resetCalibration() {
        calibrationOffset = 0.0
    }

    // MARK: - Приватные методы

    /// Обновляет текст и цвет статуса в зависимости от величины поля.
    private func updateStatus(for value: Double) {
        switch value {
        case ..<Thresholds.safe:
            statusText = "Стена чиста / Металл не обнаружен"
            statusColor = .green
        case Thresholds.safe..<Thresholds.suspicious:
            statusText = "Подозрение на металл/проводку"
            statusColor = .yellow
        default:
            statusText = "ВНИМАНИЕ! Обнаружен металл или кабель!"
            statusColor = .red
        }
    }

    /// Запускает тактильную отдачу, если значение превышает порог.
    /// Ограничиваем частоту вибрации, чтобы она не была непрерывной.
    private func triggerHapticIfNeeded(value: Double) {
        guard value > Thresholds.hapticTrigger else { return }
        let now = Date()
        // Минимальный интервал между вибрациями — 0.4 секунды.
        if now.timeIntervalSince(lastHapticTime) > 0.4 {
            hapticGenerator.impactOccurred()
            hapticGenerator.prepare() // Готовим к следующему срабатыванию.
            lastHapticTime = now
        }
    }
}

