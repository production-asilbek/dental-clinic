import SwiftUI

@main
struct ClinicApp: App {
    @StateObject private var session = SessionViewModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .task {
                    await session.bootstrap()
                }
                .onOpenURL { url in
                    Task {
                        await session.handleOpenURL(url)
                    }
                }
        }
    }
}
