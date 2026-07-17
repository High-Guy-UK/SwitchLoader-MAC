import SwiftUI

@main
struct SwitchLoaderApp: App {
    @StateObject private var model = SwitchLoaderModel()

    var body: some Scene {
        WindowGroup {
            LaunchGateView()
                .environmentObject(model)
                .frame(width: 1020, height: 620)
        }
        .defaultSize(width: 1020, height: 620)
        .windowResizability(.contentSize)
        .windowStyle(.titleBar)
    }
}

private struct LaunchGateView: View {
    @State private var isShowingSplash = true

    var body: some View {
        ZStack {
            if isShowingSplash {
                LaunchSplashView()
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
            } else {
                ContentView()
                    .transition(.opacity)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            try? await Task.sleep(for: .seconds(3))
            withAnimation(.easeInOut(duration: 0.32)) {
                isShowingSplash = false
            }
        }
    }
}

private struct LaunchSplashView: View {
    @State private var controllersSnapped = false
    @State private var screenGlow = false

    var body: some View {
        ZStack {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(nsColor: .windowBackgroundColor),
                            Color.black.opacity(0.16)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            VStack(spacing: 18) {
                AnimatedHandheldMark(
                    controllersSnapped: controllersSnapped,
                    screenGlow: screenGlow
                )
                .frame(width: 230, height: 118)

                VStack(spacing: 7) {
                    Text("SwitchLoader")
                        .font(.system(size: 34, weight: .bold, design: .rounded))

                    Text("Built for Apple silicon")
                        .font(.caption.bold())
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)

                    Text("Queue, manage, and launch your Switch workflows from Mac.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 34)
            .padding(.vertical, 26)
            .frame(width: 430, height: 286)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.18))
            }
            .shadow(color: .black.opacity(0.22), radius: 28, y: 16)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                screenGlow = true
            }

            withAnimation(.interpolatingSpring(stiffness: 170, damping: 16).delay(0.28)) {
                controllersSnapped = true
            }
        }
    }
}

private struct AnimatedHandheldMark: View {
    let controllersSnapped: Bool
    let screenGlow: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.black.opacity(0.38))
                .frame(width: 162, height: 88)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.cyan.opacity(screenGlow ? 0.44 : 0.28),
                                    Color.indigo.opacity(screenGlow ? 0.34 : 0.22),
                                    Color.black.opacity(0.74)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .padding(8)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.16))
                }
                .shadow(color: Color.cyan.opacity(screenGlow ? 0.30 : 0.10), radius: screenGlow ? 18 : 8)

            ControllerSide(isLeft: true)
                .offset(
                    x: controllersSnapped ? -88 : -74,
                    y: controllersSnapped ? 0 : -54
                )
                .rotationEffect(.degrees(controllersSnapped ? 0 : -7))

            ControllerSide(isLeft: false)
                .offset(
                    x: controllersSnapped ? 88 : 74,
                    y: controllersSnapped ? 0 : -54
                )
                .rotationEffect(.degrees(controllersSnapped ? 0 : 7))

            Capsule()
                .fill(Color.white.opacity(controllersSnapped ? 0.46 : 0))
                .frame(width: 126, height: 2)
                .offset(y: 55)
        }
    }
}

private struct ControllerSide: View {
    let isLeft: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(
                LinearGradient(
                    colors: isLeft
                        ? [Color.teal.opacity(0.88), Color.blue.opacity(0.76)]
                        : [Color.pink.opacity(0.86), Color.orange.opacity(0.76)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: 40, height: 84)
            .overlay(alignment: .top) {
                Circle()
                    .fill(Color.black.opacity(0.42))
                    .frame(width: 12, height: 12)
                    .offset(y: 16)
            }
            .overlay(alignment: .bottom) {
                VStack(spacing: 5) {
                    Circle()
                        .fill(Color.white.opacity(0.58))
                        .frame(width: 6, height: 6)
                    Circle()
                        .fill(Color.white.opacity(0.42))
                        .frame(width: 6, height: 6)
                }
                .offset(y: -16)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.22))
            }
            .shadow(color: .black.opacity(0.22), radius: 8, y: 5)
    }
}
