import SwiftUI
import ServiceManagement

struct MenuBarView: View {
    @ObservedObject var timerManager: TimerManager
    @AppStorage("workDurationMinutes") private var workDurationMinutes: Int = 20
    @AppStorage("breakDurationSeconds") private var breakDurationSeconds: Int = 20
    @AppStorage("smartPauseEnabled") private var smartPauseEnabled: Bool = true

    var body: some View {
        // Status header
        Text(timerManager.statusDescription)
            .font(.headline)

        if timerManager.smartPauseEnabled, let source = timerManager.meetingDetector.meetingSource {
            Text(source)
        }

        Divider()

        // Timer controls
        if timerManager.state == .working {
            Button("Pause Timer") {
                timerManager.togglePause()
            }
            .keyboardShortcut("p")
        } else if timerManager.state == .paused {
            Button("Resume Timer") {
                timerManager.togglePause()
            }
            .keyboardShortcut("p")
            .disabled(timerManager.meetingDetector.isInMeeting)
        }

        Button("Restart Timer") {
            timerManager.start()
        }
        .keyboardShortcut("r")

        Divider()

        // Settings inline
        Menu("Work Interval: \(workDurationMinutes) min") {
            ForEach(workIntervalOptions, id: \.self) { minutes in
                Button {
                    workDurationMinutes = minutes
                } label: {
                    if minutes == workDurationMinutes {
                        Text("\(minutes) minutes")
                    } else {
                        Text("\(minutes) minutes")
                    }
                }
            }
        }

        Menu("Break Duration: \(breakDurationSeconds) sec") {
            ForEach(breakDurationOptions, id: \.self) { seconds in
                Button {
                    breakDurationSeconds = seconds
                } label: {
                    Text(formatBreakDuration(seconds))
                }
            }
        }

        Divider()

        Toggle("Smart Pause", isOn: $smartPauseEnabled)

        Toggle("Launch at Login", isOn: Binding(
            get: { SMAppService.mainApp.status == .enabled },
            set: { newValue in
                try? newValue ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
            }
        ))

        Divider()

        Button("Quit Breaker") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private var workIntervalOptions: [Int] {
        [5, 10, 15, 20, 30, 45, 60]
    }

    private var breakDurationOptions: [Int] {
        [10, 20, 30, 60, 120, 300]
    }

    private func formatBreakDuration(_ seconds: Int) -> String {
        if seconds < 60 {
            return "\(seconds) seconds"
        } else {
            let minutes = seconds / 60
            return "\(minutes) minute\(minutes > 1 ? "s" : "")"
        }
    }
}
