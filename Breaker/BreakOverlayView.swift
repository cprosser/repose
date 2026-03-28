import SwiftUI

struct BreakOverlayView: View {
    @ObservedObject var timerManager: TimerManager
    let isPrimary: Bool
    @State private var breathe = false

    var body: some View {
        ZStack {
            // Gradient background
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.05, blue: 0.15),
                    Color(red: 0.1, green: 0.08, blue: 0.2),
                    Color(red: 0.05, green: 0.05, blue: 0.12),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            if isPrimary {
                VStack(spacing: 32) {
                    Spacer()

                    // Breathing circle animation
                    ZStack {
                        Circle()
                            .fill(.white.opacity(0.05))
                            .frame(width: 160, height: 160)
                            .scaleEffect(breathe ? 1.15 : 0.9)

                        Circle()
                            .fill(.white.opacity(0.08))
                            .frame(width: 120, height: 120)
                            .scaleEffect(breathe ? 1.1 : 0.95)

                        Image(systemName: "eye")
                            .font(.system(size: 48, weight: .thin))
                            .foregroundStyle(.white.opacity(0.9))
                    }

                    VStack(spacing: 12) {
                        Text("Take a Break")
                            .font(.system(size: 42, weight: .medium, design: .rounded))
                            .foregroundStyle(.white)

                        Text("Rest your eyes and look at something far away")
                            .font(.system(size: 18, weight: .regular))
                            .foregroundStyle(.white.opacity(0.5))
                    }

                    // Countdown
                    Text(formatTime(timerManager.remainingSeconds))
                        .font(.system(size: 80, weight: .ultraLight, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.9))
                        .contentTransition(.numericText())

                    // Skip button
                    Button(action: { timerManager.skipBreak() }) {
                        Text("Skip")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.white.opacity(0.6))
                            .padding(.horizontal, 28)
                            .padding(.vertical, 10)
                            .background(.white.opacity(0.1), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        if hovering {
                            NSCursor.pointingHand.push()
                        } else {
                            NSCursor.pop()
                        }
                    }

                    Spacer()
                }
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
                breathe = true
            }
        }
    }

    private func formatTime(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
}
