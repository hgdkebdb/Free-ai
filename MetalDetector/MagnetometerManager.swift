//
//  MagnetometerManager.swift
//  Metal & Wire Detector
//
//  Класс-менеджер для работы с магнитометром через CoreMotion.
//  Отвечает за:
//    - запуск/остановку обновлений датчика;
//    - расчёт модуля вектора магнитного поля (sqrt(x^2 + y^2 + z^2));
//    - калибровку (вычитание текущего фона из последующих замеров);
//    - тактильную отдачу при превышении порога 100 μT.
//

import Foundation
import CoreMotion
import UIKit
import Combine

/// ObservableObject, к которому SwiftUI будет подписываться через @StateObject/@ObservedObject.
/// Публикует текущее значение магнитного поля и доступность датчика.
final class MagnetometerManager: ObservableObject {

    // MARK: - Публикуемые свойства (источники истины для UI)

    /// Текущая сила магнитного поля (с учётом калибровки), в микротеслах (μT).
    @Published private(set) var fieldStrength: Double = 0.0

    /// Сырое значение |B| без учёта калибровочной поправки — на случай отладки/индикации.
    @Published private(set) var rawFieldStrength: Double = 0.0

    /// Доступен ли магнитометр на этом устройстве.
    @Published private(set) var isAvailable: Bool = false

    /// Идут ли в данный момент обновления датчика.
    @Published private(set) var isRunning: Bool = false

    // MARK: - Приватные свойства

    /// Менеджер CoreMotion, через который запрашиваются данные магнитометра.
    private let motionManager = CMMotionManager()

    /// Очередь, на которой будут приходить колбэки CoreMotion.
    /// Используем отдельную очередь, чтобы не блокировать main thread.
    private let updatesQueue: OperationQueue = {
        let q = OperationQueue()
        q.name = "com.metaldetector.magnetometer.queue"
        q.qualityOfService = .userInteractive
        return q
    }()

    /// Калибровочное (фоновое) значение, которое запоминается при нажатии "Калибровка"
    /// и затем вычитается из сырых замеров.
    private var calibrationOffset: Double = 0.0

    /// Порог в μT, при превышении которого срабатывает тактильная отдача.
    private let hapticThreshold: Double = 100.0

    /// Чтобы не вибрировать на каждом тике, держим состояние "уже выше порога?"
    private var isAboveThreshold: Bool = false

    /// Генератор тактильной отдачи (заранее подготовленный для уменьшения задержки).
    private let hapticGenerator: UIImpactFeedbackGenerator = {
        let gen = UIImpactFeedbackGenerator(style: .heavy)
        gen.prepare()
        return gen
    }()

    // MARK: - Инициализация

    init() {
        // Проверяем доступность датчика сразу, чтобы UI мог отразить состояние.
        self.isAvailable = motionManager.isMagnetometerAvailable
        // Частота обновлений датчика: 10 раз в секунду — достаточно для UI и щадяще для батареи.
        motionManager.magnetometerUpdateInterval = 1.0 / 10.0
    }

    deinit {
        // Гарантированно останавливаем датчик при уничтожении объекта.
        stop()
    }

    // MARK: - Публичный API

    /// Запускает обновления магнитометра.
    /// Если датчик недоступен — просто помечает состояние и ничего не делает.
    func start() {
        // Проверка доступности датчика — обязательное требование задачи.
        guard motionManager.isMagnetometerAvailable else {
            DispatchQueue.main.async { [weak self] in
                self?.isAvailable = false
                self?.isRunning = false
            }
            return
        }

        // Если уже запущены — выходим, чтобы не дублировать подписку.
        guard !motionManager.isMagnetometerActive else { return }

        motionManager.startMagnetometerUpdates(to: updatesQueue) { [weak self] data, error in
            guard let self = self else { return }

            // Если пришла ошибка или нет данных — пропускаем тик.
            if let _ = error { return }
            guard let field = data?.magneticField else { return }

            // Считаем модуль вектора магнитного поля: |B| = sqrt(x^2 + y^2 + z^2)
            let magnitude = sqrt(field.x * field.x +
                                 field.y * field.y +
                                 field.z * field.z)

            // Применяем калибровочный сдвиг.
            // max(..., 0) чтобы из-за шума калибровки значение не уходило в минус.
            let calibrated = max(magnitude - self.calibrationOffset, 0.0)

            // Все обновления UI и @Published-свойств — на главном потоке.
            DispatchQueue.main.async {
                self.rawFieldStrength = magnitude
                self.fieldStrength = calibrated
                self.handleHaptics(for: calibrated)
            }
        }

        DispatchQueue.main.async { [weak self] in
            self?.isRunning = true
        }
    }

    /// Останавливает обновления магнитометра.
    func stop() {
        if motionManager.isMagnetometerActive {
            motionManager.stopMagnetometerUpdates()
        }
        DispatchQueue.main.async { [weak self] in
            self?.isRunning = false
        }
    }

    /// Калибровка: запоминаем текущее "сырое" показание как фон
    /// и в дальнейшем вычитаем его из последующих замеров.
    func calibrate() {
        // В качестве фона берём последнее сырое значение |B|.
        calibrationOffset = rawFieldStrength

        // Сразу обновим отображаемое значение, чтобы UI среагировал мгновенно.
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.fieldStrength = max(self.rawFieldStrength - self.calibrationOffset, 0.0)
            self.isAboveThreshold = false
        }
    }

    /// Сброс калибровки (если потребуется в дальнейшем).
    func resetCalibration() {
        calibrationOffset = 0.0
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.fieldStrength = self.rawFieldStrength
        }
    }

    // MARK: - Приватные хелперы

    /// Управление тактильной отдачей в зависимости от текущего значения поля.
    /// Срабатывает в момент пересечения порога (а не на каждом тике), чтобы не "трясло" постоянно.
    private func handleHaptics(for value: Double) {
        if value >= hapticThreshold {
            // Если только что пересекли порог — даём ощутимый импульс.
            if !isAboveThreshold {
                hapticGenerator.impactOccurred()
                hapticGenerator.prepare() // подготовка к следующему срабатыванию
                isAboveThreshold = true
            } else {
                // Уже находимся выше порога — даём более лёгкие повторные импульсы,
                // чтобы пользователь чувствовал, что металл рядом.
                hapticGenerator.impactOccurred(intensity: 0.6)
            }
        } else {
            // Опустились ниже порога — сбрасываем флаг, чтобы при следующем превышении снова "стукнуло".
            isAboveThreshold = false
        }
    }
}
