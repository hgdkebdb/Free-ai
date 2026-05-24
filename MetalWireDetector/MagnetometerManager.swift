//
//  MagnetometerManager.swift
//  Metal & Wire Detector
//
//  Класс, отвечающий за получение данных с магнитометра устройства
//  через CoreMotion. Считает модуль вектора магнитного поля,
//  поддерживает калибровку и публикует значения для SwiftUI.
//

import Foundation
import CoreMotion
import UIKit
import Combine

/// Основной менеджер магнитометра.
/// Использует `ObservableObject`, чтобы SwiftUI автоматически
/// перерисовывал интерфейс при изменении значений.
final class MagnetometerManager: ObservableObject {

    // MARK: - Публичные свойства (отслеживаются SwiftUI)

    /// Текущее «итоговое» значение силы магнитного поля в микротеслах (μT)
    /// после вычитания калибровочного смещения.
    @Published var magneticFieldStrength: Double = 0.0

    /// «Сырое» (некалиброванное) значение модуля вектора магнитного поля.
    /// Используется для калибровки и отладки.
    @Published var rawMagneticFieldStrength: Double = 0.0

    /// Признак того, что датчик доступен на устройстве.
    @Published var isSensorAvailable: Bool = false

    /// Сообщение об ошибке (если что-то пошло не так).
    @Published var errorMessage: String? = nil

    /// Признак того, что калибровка выполнена хотя бы один раз.
    @Published var isCalibrated: Bool = false

    // MARK: - Внутренние свойства

    /// Объект CoreMotion, который непосредственно общается с датчиком.
    private let motionManager = CMMotionManager()

    /// Очередь, на которой будут приходить обновления данных от датчика.
    private let updateQueue = OperationQueue()

    /// Калибровочное смещение — фоновое значение поля,
    /// которое вычитается из последующих замеров.
    private var calibrationOffset: Double = 0.0

    /// Генератор тактильной отдачи — создаём один раз и переиспользуем,
    /// чтобы не плодить лишние объекты на каждый кадр.
    private let hapticGenerator = UIImpactFeedbackGenerator(style: .heavy)

    /// Минимальный интервал между вибрациями (в секундах), чтобы
    /// телефон не «дребезжал» слишком часто при превышении порога.
    private let hapticCooldown: TimeInterval = 0.5

    /// Время последней сработавшей вибрации.
    private var lastHapticTime: Date = .distantPast

    /// Порог, при превышении которого срабатывает тактильная отдача.
    private let hapticThreshold: Double = 100.0

    // MARK: - Инициализация

    init() {
        // Настраиваем имя очереди для удобной отладки.
        updateQueue.name = "com.metalwiredetector.magnetometer.queue"
        updateQueue.qualityOfService = .userInteractive

        // Сразу проверяем доступность магнитометра на устройстве.
        // На некоторых устройствах (или в симуляторе) его может не быть.
        self.isSensorAvailable = motionManager.isMagnetometerAvailable

        if !self.isSensorAvailable {
            self.errorMessage = "Магнитометр недоступен на этом устройстве. " +
                                "Запустите приложение на реальном iPhone."
        }

        // «Подготавливаем» генератор тактильной отдачи,
        // чтобы первая вибрация сработала без задержки.
        hapticGenerator.prepare()
    }

    deinit {
        // На всякий случай гарантированно останавливаем датчик
        // при уничтожении менеджера, чтобы не утекал энергорасход.
        stopUpdates()
    }

    // MARK: - Публичный API

    /// Запускает регулярное получение данных от магнитометра.
    func startUpdates() {
        // Если датчик недоступен — выходим, чтобы не падать.
        guard motionManager.isMagnetometerAvailable else {
            self.errorMessage = "Магнитометр недоступен на этом устройстве."
            return
        }

        // Если обновления уже идут — не запускаем второй раз.
        guard !motionManager.isMagnetometerActive else { return }

        // Период обновления в секундах. 10 Гц достаточно для плавного UI
        // и при этом не сильно нагружает батарею.
        motionManager.magnetometerUpdateInterval = 1.0 / 10.0

        // Запускаем поток данных. Обновления приходят на нашу фоновую очередь.
        motionManager.startMagnetometerUpdates(to: updateQueue) { [weak self] data, error in
            guard let self = self else { return }

            // Обрабатываем возможную ошибку датчика.
            if let error = error {
                DispatchQueue.main.async {
                    self.errorMessage = "Ошибка магнитометра: \(error.localizedDescription)"
                }
                return
            }

            // Проверяем, что данные пришли.
            guard let field = data?.magneticField else { return }

            // Считаем модуль вектора магнитного поля по теореме Пифагора в 3D:
            // |B| = sqrt(x² + y² + z²)
            let magnitude = sqrt(
                field.x * field.x +
                field.y * field.y +
                field.z * field.z
            )

            // Вычитаем калибровочный фон. Не даём значению уйти ниже нуля.
            let calibrated = max(0.0, magnitude - self.calibrationOffset)

            // Все обновления UI и @Published-свойств — только в главном потоке.
            DispatchQueue.main.async {
                self.rawMagneticFieldStrength = magnitude
                self.magneticFieldStrength = calibrated
                self.triggerHapticIfNeeded(for: calibrated)
            }
        }
    }

    /// Останавливает поток данных от магнитометра.
    func stopUpdates() {
        if motionManager.isMagnetometerActive {
            motionManager.stopMagnetometerUpdates()
        }
    }

    /// Калибровка: запоминаем текущее «сырое» значение
    /// как фоновое и вычитаем его из всех последующих замеров.
    func calibrate() {
        // В качестве смещения берём последнее сырое значение поля.
        // Это считается «нулевым уровнем» для пользователя.
        calibrationOffset = rawMagneticFieldStrength
        isCalibrated = true

        // Сразу же обновляем отображаемое значение,
        // чтобы индикатор «упал в ноль» в момент калибровки.
        magneticFieldStrength = 0.0
    }

    /// Сбрасывает калибровку (возвращает «сырые» показания).
    func resetCalibration() {
        calibrationOffset = 0.0
        isCalibrated = false
        magneticFieldStrength = rawMagneticFieldStrength
    }

    // MARK: - Приватные методы

    /// Триггерит тактильную отдачу, если значение превысило порог
    /// и с момента предыдущей вибрации прошло достаточно времени.
    private func triggerHapticIfNeeded(for value: Double) {
        guard value > hapticThreshold else { return }

        let now = Date()
        if now.timeIntervalSince(lastHapticTime) >= hapticCooldown {
            // Сама вибрация. impactOccurred — это короткий «удар».
            hapticGenerator.impactOccurred()
            // Сразу подготавливаем генератор к следующему срабатыванию.
            hapticGenerator.prepare()
            lastHapticTime = now
        }
    }
}
