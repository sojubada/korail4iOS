import SwiftUI

@main
struct Korail4App: App {
    @StateObject private var app = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(app)
                .task { await app.bootstrap() }
        }
    }
}

struct RootView: View {
    var body: some View {
        TabView {
            SearchView()
                .tabItem { Label("조회·예약", systemImage: "magnifyingglass") }
            MyTicketsView()
                .tabItem { Label("내 예약", systemImage: "ticket") }
            AccountView()
                .tabItem { Label("계정", systemImage: "person.crop.circle") }
        }
    }
}
