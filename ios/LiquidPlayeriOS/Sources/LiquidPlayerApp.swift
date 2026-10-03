import SwiftUI

@main
struct LiquidPlayerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                #if targetEnvironment(macCatalyst)
                .frame(minWidth: 500, minHeight: 650)
                #endif
        }
        #if targetEnvironment(macCatalyst)
        .defaultSize(width: 1024, height: 768)
        #endif
    }
}
