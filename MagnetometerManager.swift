import Foundation
import CoreMotion
import Combine
import UIKit

// MARK: - Режимы работы детектора

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

// MARK: - Состояние точности датчика (для UI-подсказок)

enum SensorAccuracy: Equatable {
    case uncalibrated
    case low
    case medium
    case high

    var needsCalibrationHint: Bool {
        self == .uncalibrated || self == .low
    }

    var hintText: String? {
        guard needsCalibrationHint else { return nil }
        return "Покрутите телефон восьмёркой для настройки датчика"
    }
}

// MARK: - Менеджер магнитометра

// Отвечает за получение данных Device Motion (магнитометр + гироскоп),
// сглаживание показаний, калибровку фона, расчёт AC-составляющей и
// тактильную отдачу.
//
// Потокобезопасность: внутреннее состояние (backgroundNoise, sampleWindow,
// filteredMagnitude, lastRawMagnitude) изменяется ИСКЛЮЧИТЕЛЬНО на
// motionQueue (maxConcurrentOperationCount = 1 → сериализация). Команды
// извне (calibrate, stopUpdates) ставятся в эту же очередь. Публикуемые
// @Published свойства обновляются только из главного потока.
final class MagnetometerManager: ObservableObject {

    // MARK: Публикуемые свойства (для UI)

    // Сглаженная DC-составляющая поля за вычетом фона — для режима «Металл».
    @Published var magneticFieldStrength: Double = 0.0

    // Амплитуда переменной составляющей (μT) — для режима «Провод 220В».
    @Published var acAmplitude: Double = 0.0

    // Текущий режим работы.
    @Published var mode: DetectorMode = .metal

    // Признак того, что датчик в принципе доступен на устройстве.
    @Published var isAvailable: Bool = true

    // Точность калибровки магнитометра, сообщаемая системой.
    @Published var accuracy: SensorAccuracy = .uncalibrated

    // Телефон активно двигается — AC-замер недостоверен, надо подержать.
    @Published var isPhoneMoving: Bool = false

    // MARK: Внутреннее состояние (только на motionQueue!)

    private var backgroundNoise: Double = 0.0
    private var lastRawMagnitude: Double = 0.0
    private var filteredMagnitude: Double = 0.0

    // Коэффициент Low-Pass Filter: new*α + old*(1-α). Чем меньше — тем плавнее.
    private let lpfAlpha: Double = 0.15

    // Скользящее окно «сырых» замеров — для расчёта AC-амплитуды.
    private var sampleWindow: [Double] = []
    private let windowSize = 60   // ≈ 0.6 с при 100 Гц

    // Порог пользовательского ускорения (в g), выше которого считаем,
    // что телефон активно двигается. 1 g ≈ 9.81 м/с². 0.06 g — спокойное
    // удержание в руке с лёгким дрожанием.
    private let motionThreshold: Double = 0.06

    // MARK: CoreMotion

    private let motionManager = CMMotionManager()
    private let motionQueue: OperationQueue = {
        let q = OperationQueue()
        q.name = "com.metaldetector.motionQueue"
        q.maxConcurrentOperationCount = 1   // строгая сериализация
        q.qualityOfService = .userInteractive
        return q
    }()

    // MARK: Тактильная отдача

    private let hapticGenerator = UIImpactFeedbackGenerator(style: .heavy)
    private var lastHapticTime: Date = .distantPast
    private let metalHapticThreshold: Double = 100.0
    private let wireHapticThreshold: Double = 3.0

    // MARK: Инициализация

    init() {
        // Проверка: устройство в принципе поддерживает нужный референс-фрейм.
        // .xArbitraryCorrectedZVertical требует магнитометра + гироскопа;
        // если его нет в наборе — Device Motion не запустится корректно.
        let supportedFrames = CMMotionManager.availableAttitudeReferenceFrames()
        let hasRequiredFrame = supportedFrames.contains(.xArbitraryCorrectedZVertical)

        guard motionManager.isDeviceMotionAvailable, hasRequiredFrame else {
            self.isAvailable = false
            return
        }

        // 100 Гц — чтобы успевать ловить колебания поля 50/60 Гц от сети.
        motionManager.deviceMotionUpdateInterval = 0.01

        hapticGenerator.prepare()
    }

    // MARK: Управление обновлениями

    // Запуск Device Motion с привязкой опорной системы координат к вертикали.
    // .xArbitraryCorrectedZVertical использует и магнитометр, и гироскоп —
    // вращения самого телефона компенсируются, остаются только реальные
    // изменения внешнего поля.
    func startUpdates() {
        guard isAvailable else { return }
        guard !motionManager.isDeviceMotionActive else { return }

        motionManager.startDeviceMotionUpdates(
            using: .xArbitraryCorrectedZVertical,
            to: motionQueue
        ) { [weak self] motion, error in
            guard let self = self, let motion = motion, error == nil else { return }
            self.process(motion: motion)
        }
    }

    // Останавливаем датчик и сбрасываем накопленное состояние.
    // Сброс делаем в motionQueue, чтобы не было гонок с активными колбэками.
    func stopUpdates() {
        if motionManager.isDeviceMotionActive {
            motionManager.stopDeviceMotionUpdates()
        }
        motionQueue.addOperation { [weak self] in
            guard let self = self else { return }
            self.sampleWindow.removeAll(keepingCapacity: true)
            self.filteredMagnitude = 0.0
            self.lastRawMagnitude = 0.0
        }
    }

    // MARK: Калибровка фона (тарирование)

    // Запоминает текущее «сырое» значение как фоновый шум комнаты.
    // Дальше из всех замеров оно вычитается.
    // Все операции над внутренним состоянием уходят в motionQueue, чтобы
    // избежать гонки данных.
    func calibrate() {
        motionQueue.addOperation { [weak self] in
            guard let self = self else { return }
            self.backgroundNoise = self.lastRawMagnitude
            self.filteredMagnitude = 0.0

            DispatchQueue.main.async {
                self.magneticFieldStrength = 0.0
            }
        }
    }

    // Сброс калибровки
    func resetCalibration() {
        motionQueue.addOperation { [weak self] in
            self?.backgroundNoise = 0.0
        }
    }

    // MARK: Обработка одного замера

    private func process(motion: CMDeviceMotion) {
        let calibratedField = motion.magneticField

        // 1. Модуль вектора магнитного поля
        let field = calibratedField.field
        let rawMagnitude = sqrt(field.x * field.x + field.y * field.y + field.z * field.z)
        lastRawMagnitude = rawMagnitude

        // 2. Оценка собственного движения телефона.
        //    userAcceleration уже без гравитации (в g).
        //    Если телефоном активно двигают — окно AC-замеров «загрязняется»
        //    реальными перемещениями в неоднородном поле Земли, и AC даёт
        //    ложные срабатывания.
        let ua = motion.userAcceleration
        let userAccMagnitude = sqrt(ua.x * ua.x + ua.y * ua.y + ua.z * ua.z)
        let phoneIsMoving = userAccMagnitude > motionThreshold

        // 3. AC-режим: накапливаем только когда телефон неподвижен.
        //    При движении окно сбрасываем — иначе старые «загрязнённые»
        //    отсчёты продолжат портить дисперсию.
        let acValue: Double
        if phoneIsMoving {
            sampleWindow.removeAll(keepingCapacity: true)
            acValue = 0.0
        } else {
            sampleWindow.append(rawMagnitude)
            if sampleWindow.count > windowSize {
                sampleWindow.removeFirst(sampleWindow.count - windowSize)
            }
            acValue = sampleWindow.count >= 10
                ? computeAcAmplitude(samples: sampleWindow)
                : 0.0
        }

        // 4. DC-составляющая: вычитаем фон → пропускаем через LPF.
        //    Сглаживание убирает микро-дрожание от внутренних токов и
        //    нагрева процессора, но движение по стене (для поиска металла)
        //    при этом не теряется — LPF лишь делает реакцию плавной.
        let backgroundCorrected = max(0.0, rawMagnitude - backgroundNoise)
        filteredMagnitude = backgroundCorrected * lpfAlpha + filteredMagnitude * (1.0 - lpfAlpha)
        let dcValue = filteredMagnitude

        // 5. Точность калибровки магнитометра
        let mappedAccuracy = Self.map(calibratedField.accuracy)

        // 6. Публикация в UI и тактильная отдача — только из главного потока.
        DispatchQueue.main.async {
            self.accuracy = mappedAccuracy
            self.magneticFieldStrength = dcValue
            self.acAmplitude = acValue
            self.isPhoneMoving = phoneIsMoving

            // При низкой точности или активном движении значения недостоверны
            // — вибрировать не нужно.
            if !mappedAccuracy.needsCalibrationHint && !phoneIsMoving {
                self.triggerHapticIfNeeded(dc: dcValue, ac: acValue)
            }
        }
    }

    // Маппинг CMMagneticFieldCalibrationAccuracy в наш enum
    private static func map(_ raw: CMMagneticFieldCalibrationAccuracy) -> SensorAccuracy {
        switch raw {
        case .uncalibrated: return .uncalibrated
        case .low:          return .low
        case .medium:       return .medium
        case .high:         return .high
        @unknown default:   return .low
        }
    }

    // MARK: AC-амплитуда

    // Стандартное отклонение окна × √2 ≈ амплитуда синусоиды.
    // У постоянного поля разброс маленький → AC ≈ 0.
    // Рядом с проводом 220В разброс растёт.
    private func computeAcAmplitude(samples: [Double]) -> Double {
        let n = Double(samples.count)
        let mean = samples.reduce(0, +) / n
        let variance = samples.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / n
        return sqrt(variance) * sqrt(2.0)
    }

    // MARK: Тактильная отдача

    private func triggerHapticIfNeeded(dc: Double, ac: Double) {
        let exceeded: Bool
        switch mode {
        case .metal:    exceeded = dc > metalHapticThreshold
        case .liveWire: exceeded = ac > wireHapticThreshold
        }
        guard exceeded else { return }

        let now = Date()
        if now.timeIntervalSince(lastHapticTime) > 0.3 {
            hapticGenerator.impactOccurred()
            hapticGenerator.prepare()
            lastHapticTime = now
        }
    }
}
