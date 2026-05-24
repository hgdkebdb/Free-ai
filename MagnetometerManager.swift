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

    // Нужно ли показать пользователю подсказку «покрутите восьмёркой»
    var needsCalibrationHint: Bool {
        self == .uncalibrated || self == .low
    }

    // Текст подсказки (если нужен)
    var hintText: String? {
        guard needsCalibrationHint else { return nil }
        return "Покрутите телефон восьмёркой для настройки датчика"
    }
}

// MARK: - Менеджер магнитометра

// Отвечает за получение данных Device Motion (магнитометр + гироскоп),
// сглаживание показаний, калибровку фона, расчёт AC-составляющей и
// тактильную отдачу.
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

    // MARK: Внутреннее состояние

    // Фоновый шум комнаты — вычитается из «сырого» значения после калибровки.
    private var backgroundNoise: Double = 0.0

    // Последний «сырой» модуль вектора (без вычитания фона, без сглаживания).
    // Нужен для калибровки, чтобы взять актуальное значение.
    private var lastRawMagnitude: Double = 0.0

    // Накопитель Low-Pass Filter (по формуле new*α + old*(1-α)).
    private var filteredMagnitude: Double = 0.0

    // Коэффициент LPF — чем меньше, тем сильнее сглаживание.
    // 0.15 → новое значение даёт 15% веса, старое 85%.
    private let lpfAlpha: Double = 0.15

    // Скользящее окно последних «сырых» замеров — для расчёта AC-амплитуды.
    private var sampleWindow: [Double] = []
    private let windowSize = 60   // ≈ 0.6 с при частоте 100 Гц

    // CoreMotion
    private let motionManager = CMMotionManager()
    private let motionQueue = OperationQueue()

    // Тактильная отдача
    private let hapticGenerator = UIImpactFeedbackGenerator(style: .heavy)
    private var lastHapticTime: Date = .distantPast
    private let metalHapticThreshold: Double = 100.0
    private let wireHapticThreshold: Double = 3.0

    // MARK: Инициализация

    init() {
        // Device Motion требует и магнитометра, и гироскопа.
        guard motionManager.isDeviceMotionAvailable,
              motionManager.isMagnetometerAvailable else {
            self.isAvailable = false
            return
        }

        // 100 Гц — чтобы успевать ловить колебания поля 50/60 Гц от сети.
        motionManager.deviceMotionUpdateInterval = 0.01

        // Подготовка генератора вибрации
        hapticGenerator.prepare()
    }

    // MARK: Управление обновлениями

    // Запуск Device Motion с привязкой опорной системы координат к вертикали.
    // .xArbitraryCorrectedZVertical использует и магнитометр, и гироскоп —
    // вращения самого телефона компенсируются, остаются только реальные
    // изменения внешнего поля.
    func startUpdates() {
        guard motionManager.isDeviceMotionAvailable,
              motionManager.isMagnetometerAvailable else {
            self.isAvailable = false
            return
        }

        // Если уже запущено — выходим, чтобы не плодить обработчики.
        guard !motionManager.isDeviceMotionActive else { return }

        motionManager.startDeviceMotionUpdates(
            using: .xArbitraryCorrectedZVertical,
            to: motionQueue
        ) { [weak self] motion, error in
            guard let self = self, let motion = motion, error == nil else { return }
            self.process(motion: motion)
        }
    }

    // Останавливаем датчик и сбрасываем накопленное состояние,
    // чтобы при следующем запуске не было «всплеска» от старых данных.
    func stopUpdates() {
        if motionManager.isDeviceMotionActive {
            motionManager.stopDeviceMotionUpdates()
        }
        sampleWindow.removeAll(keepingCapacity: true)
        filteredMagnitude = 0.0
        lastRawMagnitude = 0.0
    }

    // MARK: Калибровка фона (тарирование)

    // Запоминает текущее «сырое» значение как фоновый шум комнаты.
    // Дальше из всех замеров это значение вычитается.
    func calibrate() {
        backgroundNoise = lastRawMagnitude

        // Сразу обнуляем UI-значение и фильтр, чтобы стрелка прыгнула в ноль.
        DispatchQueue.main.async {
            self.filteredMagnitude = 0.0
            self.magneticFieldStrength = 0.0
        }
    }

    // Сброс калибровки (если потребуется)
    func resetCalibration() {
        backgroundNoise = 0.0
    }

    // MARK: Обработка одного замера

    private func process(motion: CMDeviceMotion) {
        let calibratedField = motion.magneticField
        let field = calibratedField.field

        // 1. Модуль вектора магнитного поля
        let rawMagnitude = sqrt(field.x * field.x + field.y * field.y + field.z * field.z)
        lastRawMagnitude = rawMagnitude

        // 2. Окно сырых замеров — для AC-режима.
        //    Для переменной составляющей сглаживать НЕЛЬЗЯ: фильтр стёр бы
        //    те самые колебания, которые мы и пытаемся найти.
        sampleWindow.append(rawMagnitude)
        if sampleWindow.count > windowSize {
            sampleWindow.removeFirst(sampleWindow.count - windowSize)
        }
        let acValue = sampleWindow.count >= 10
            ? computeAcAmplitude(samples: sampleWindow)
            : 0.0

        // 3. DC-составляющая: вычитаем фон → пропускаем через LPF.
        let backgroundCorrected = max(0.0, rawMagnitude - backgroundNoise)
        filteredMagnitude = backgroundCorrected * lpfAlpha + filteredMagnitude * (1.0 - lpfAlpha)
        let dcValue = filteredMagnitude

        // 4. Точность калибровки магнитометра — для подсказки в UI.
        let mappedAccuracy = Self.map(calibratedField.accuracy)

        // 5. Публикуем результат в главном потоке.
        DispatchQueue.main.async {
            self.accuracy = mappedAccuracy
            self.magneticFieldStrength = dcValue
            self.acAmplitude = acValue

            // При низкой точности значения «случайные» — вибрировать не нужно.
            if !mappedAccuracy.needsCalibrationHint {
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
