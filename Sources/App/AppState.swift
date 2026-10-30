import SwiftUI

@MainActor
final class AppState: ObservableObject {
    let client = KorailClient()
    @Published var isLoggedIn = false
    @Published var member: Member?
    @Published var stations: [Station] = []
    @Published var banner: String?

    /// 앱 시작 시: 자동 로그인 + 역 목록 로드
    func bootstrap() async {
        if let c = KeychainStore.load(), let t = LoginIDType(rawValue: c.idType) {
            do {
                try await client.login(id: c.id, password: c.password, idType: t)
                isLoggedIn = client.isLoggedIn
                member = client.member
            } catch {
                banner = "자동 로그인 실패: \(error.localizedDescription)"
            }
        }
        await loadStations()
    }

    func login(id: String, password: String, idType: LoginIDType, remember: Bool) async throws {
        try await client.login(id: id, password: password, idType: idType)
        isLoggedIn = client.isLoggedIn
        member = client.member
        if remember {
            KeychainStore.save(Credentials(idType: idType.rawValue, id: id, password: password))
        }
    }

    func logout() async {
        await client.logout()
        isLoggedIn = false
        member = nil
    }

    func forget() { KeychainStore.clear() }

    func loadStations() async {
        do { stations = try await client.stations() }
        catch { /* 실패해도 조회는 수동으로 가능 */ }
    }
}
