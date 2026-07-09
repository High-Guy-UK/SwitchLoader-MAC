import SwiftUI

@main
struct SwitchLoaderApp: App {
    @StateObject private var model = SwitchLoaderModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .frame(width: 1020, height: 460)
        }
        .defaultSize(width: 1020, height: 460)
        .windowResizability(.contentSize)
        .windowStyle(.titleBar)
    }
}
