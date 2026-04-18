import Foundation
import Combine
import AppKit
import CoreGraphics
import IOKit.pwr_mgt

enum TimerState {
    case working
    case onBreak
    case paused
}

enum PauseReason {
    case manual
    case meeting
    case inactive
}

enum SettingsKey {
    static let workDurationMinutes = "workDurationMinutes"
    static let breakDurationSeconds = "breakDurationSeconds"
    static let pauseDuringMeetings = "pauseDuringMeetings"
    static let ignoreMicrophoneForMeetingDetection = "ignoreMicrophoneForMeetingDetection"
    static let allowSkipBreak = "allowSkipBreak"
    static let muteSounds = "muteSounds"
    static let naturalBreakDetection = "pauseWhenIdle"
}

@MainActor
class TimerManager: ObservableObject {
    @Published var state: TimerState = .working
    @Published var remainingSeconds: Int = 0

    private var timerCancellable: AnyCancellable?
    private var tickCount: Int = 0
    private var secondsBeforePause: Int = 0
    private var pauseReason: PauseReason = .manual
    private var inactivityBeganAt: Date?
    private var sleepBeganAt: Date?
    private var naturalBreakSatisfied = false

    let meetingDetector = MeetingDetector()
    let overlayManager = OverlayManager()

    // Activity to prevent App Nap
    private var activity: NSObjectProtocol?

    var workDurationSeconds: Int {
        UserDefaults.standard.integer(forKey: SettingsKey.workDurationMinutes).clamped(to: 1...120) * 60
    }

    var breakDurationSeconds: Int {
        let val = UserDefaults.standard.integer(forKey: SettingsKey.breakDurationSeconds)
        return val.clamped(to: 5...300)
    }

    var pauseDuringMeetings: Bool {
        UserDefaults.standard.bool(forKey: SettingsKey.pauseDuringMeetings)
    }

    var muteSounds: Bool {
        UserDefaults.standard.bool(forKey: SettingsKey.muteSounds)
    }

    var naturalBreakDetectionEnabled: Bool {
        UserDefaults.standard.bool(forKey: SettingsKey.naturalBreakDetection)
    }

    var menuBarText: String {
        switch state {
        case .working:
            return formatTime(remainingSeconds)
        case .onBreak:
            return "Break \(formatTime(remainingSeconds))"
        case .paused:
            switch pauseReason {
            case .meeting:
                return "Meeting \(formatTime(secondsBeforePause))"
            case .inactive:
                return naturalBreakSatisfied ? "Natural Break" : "Inactive"
            case .manual:
                return "Paused \(formatTime(secondsBeforePause))"
            }
        }
    }

    var pauseStatusText: String? {
        guard state == .paused else { return nil }
        switch pauseReason {
        case .meeting:
            return meetingDetector.meetingSource.map { "Paused — \($0)" } ?? "Paused — Meeting"
        case .inactive:
            return naturalBreakSatisfied ? "Paused — Natural Break" : "Paused — Inactive"
        case .manual:
            return "Paused"
        }
    }

    var currentPauseReason: PauseReason? {
        state == .paused ? pauseReason : nil
    }

    var hasSatisfiedNaturalBreak: Bool {
        state == .paused && pauseReason == .inactive && naturalBreakSatisfied
    }

    init() {
        // Register defaults
        UserDefaults.standard.register(defaults: [
            SettingsKey.workDurationMinutes: 20,
            SettingsKey.breakDurationSeconds: 20,
            SettingsKey.pauseDuringMeetings: true,
            SettingsKey.ignoreMicrophoneForMeetingDetection: false,
            SettingsKey.allowSkipBreak: true,
            SettingsKey.muteSounds: false,
            SettingsKey.naturalBreakDetection: true,
        ])
        // Start timer and ticker (ticker runs for app lifetime)
        remainingSeconds = workDurationSeconds
        state = .working
        startTicking()

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleWillSleep()
            }
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleWake()
            }
        }
    }

    private func handleWillSleep() {
        sleepBeganAt = Date()

        guard naturalBreakDetectionEnabled else { return }

        if state == .working, let sleepBeganAt {
            enterInactivityPause(at: sleepBeganAt)
        }
    }

    private func handleWake() {
        defer { sleepBeganAt = nil }

        if naturalBreakDetectionEnabled,
           state == .paused,
           pauseReason == .inactive {
            resumeFromInactivity(shouldResumeImmediately: true)
            return
        }

        switch state {
        case .working:
            remainingSeconds = workDurationSeconds
        case .onBreak:
            overlayManager.dismissOverlay()
            remainingSeconds = workDurationSeconds
            state = .working
        case .paused:
            break
        }
    }

    func start() {
        clearInactivitySession()
        remainingSeconds = workDurationSeconds
        state = .working
        pauseReason = .manual
    }

    func pause() {
        guard state == .working else { return }
        clearInactivitySession()
        secondsBeforePause = remainingSeconds
        state = .paused
        pauseReason = .manual
    }

    func resume() {
        guard state == .paused else { return }
        clearInactivitySession()
        remainingSeconds = secondsBeforePause
        state = .working
        pauseReason = .manual
    }

    func skipBreak() {
        clearInactivitySession()
        overlayManager.dismissOverlay()
        remainingSeconds = workDurationSeconds
        state = .working
    }

    func togglePause() {
        if state == .working {
            pause()
        } else if state == .paused && pauseReason != .meeting {
            if pauseReason == .inactive {
                resumeFromInactivity(shouldResumeImmediately: true)
            } else {
                resume()
            }
        }
    }

    // MARK: - Private

    private func startTicking() {
        activity = ProcessInfo.processInfo.beginActivity(
            options: .userInitiated,
            reason: "Break timer running"
        )

        timerCancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.tick()
            }
    }

    private func tick() {
        tickCount += 1

        if naturalBreakDetectionEnabled {
            checkInactivityStatus()
        }

        // Check for meetings every 5 seconds
        if tickCount % 5 == 0 {
            if pauseDuringMeetings { checkMeetingStatus() }
        }

        switch state {
        case .paused:
            break

        case .working:
            remainingSeconds -= 1
            if remainingSeconds <= 0 {
                startBreak()
            }

        case .onBreak:
            remainingSeconds -= 1
            if remainingSeconds <= 0 {
                endBreak()
            }
        }
    }

    private func startBreak() {
        // Check for meeting immediately before showing break overlay
        if pauseDuringMeetings {
            meetingDetector.check()
            if meetingDetector.isInMeeting {
                secondsBeforePause = workDurationSeconds
                state = .paused
                pauseReason = .meeting
                return
            }
        }

        remainingSeconds = breakDurationSeconds
        state = .onBreak
        overlayManager.showBreakOverlay(timerManager: self)
        if !muteSounds { NSSound(named: "Glass")?.play() }
    }

    private func endBreak() {
        if !muteSounds { NSSound(named: "Blow")?.play() }
        overlayManager.dismissWithAnimation()
        remainingSeconds = workDurationSeconds
        state = .working
    }

    private func checkMeetingStatus() {
        meetingDetector.check()

        if meetingDetector.isInMeeting {
            if state == .working {
                secondsBeforePause = remainingSeconds
                state = .paused
                pauseReason = .meeting
            } else if state == .onBreak {
                // If a meeting starts during a break, skip the break
                skipBreak()
                secondsBeforePause = remainingSeconds
                state = .paused
                pauseReason = .meeting
            }
        } else {
            if state == .paused && pauseReason == .meeting {
                // Meeting ended, resume
                resume()
            }
        }
    }

    // MARK: - Inactivity Detection

    private let inactivityPauseThreshold: TimeInterval = 10

    private func checkInactivityStatus() {
        // kCGAnyInputEventType (~0) checks all input event types
        let inactivityDuration = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
        let shouldPauseForInactivity = inactivityDuration >= inactivityPauseThreshold && !hasActiveDisplaySleepAssertion()

        if shouldPauseForInactivity {
            if state == .working {
                enterInactivityPause(at: Date())
            } else if state == .paused && pauseReason == .inactive {
                updateNaturalBreakProgress()
            }
        } else {
            if state == .paused && pauseReason == .inactive {
                resumeFromInactivity(shouldResumeImmediately: true)
            }
        }
    }

    private func enterInactivityPause(at startDate: Date) {
        guard state == .working else { return }

        secondsBeforePause = remainingSeconds
        inactivityBeganAt = startDate
        naturalBreakSatisfied = false
        state = .paused
        pauseReason = .inactive
    }

    private func updateNaturalBreakProgress(referenceDate: Date = Date()) {
        guard pauseReason == .inactive,
              let inactivityBeganAt,
              !naturalBreakSatisfied else { return }

        if referenceDate.timeIntervalSince(inactivityBeganAt) >= TimeInterval(workDurationSeconds) {
            naturalBreakSatisfied = true
            secondsBeforePause = workDurationSeconds
            remainingSeconds = workDurationSeconds
        }
    }

    private func resumeFromInactivity(shouldResumeImmediately: Bool) {
        guard state == .paused && pauseReason == .inactive else { return }

        updateNaturalBreakProgress()
        let resumeSeconds = naturalBreakSatisfied ? workDurationSeconds : secondsBeforePause

        // Check for active meeting before resuming to avoid a gap
        if pauseDuringMeetings {
            meetingDetector.check()
            if meetingDetector.isInMeeting {
                secondsBeforePause = resumeSeconds
                inactivityBeganAt = nil
                naturalBreakSatisfied = false
                pauseReason = .meeting
                return
            }
        }

        clearInactivitySession()
        remainingSeconds = resumeSeconds

        if shouldResumeImmediately {
            state = .working
            pauseReason = .manual
        }
    }

    private func clearInactivitySession() {
        inactivityBeganAt = nil
        naturalBreakSatisfied = false
    }

    private func hasActiveDisplaySleepAssertion() -> Bool {
        var assertions: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&assertions) == kIOReturnSuccess,
              let dict = assertions?.takeRetainedValue() as? [String: [[String: Any]]] else {
            return false
        }

        for (_, processAssertions) in dict {
            for assertion in processAssertions {
                if let type = assertion["AssertType"] as? String,
                   type == "PreventUserIdleDisplaySleep" || type == "NoDisplaySleep" {
                    return true
                }
            }
        }
        return false
    }

}

func formatTime(_ seconds: Int) -> String {
    let m = seconds / 60
    let s = seconds % 60
    return String(format: "%d:%02d", m, s)
}

extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
