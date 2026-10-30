import SwiftUI

struct MyTicketsView: View {
    @EnvironmentObject var app: AppState
    @State private var items: [[String: Any]] = []
    @State private var error: String?
    @State private var loading = false

    var body: some View {
        NavigationStack {
            List {
                if !app.isLoggedIn {
                    Text("로그인이 필요합니다 (계정 탭).").foregroundStyle(.secondary)
                }
                if let e = error { Text(e).foregroundStyle(.red).font(.footnote) }
                ForEach(items.indices, id: \.self) { i in
                    row(items[i])
                }
                if app.isLoggedIn && items.isEmpty && !loading && error == nil {
                    Text("예약 내역이 없습니다.").foregroundStyle(.secondary)
                }
            }
            .navigationTitle("내 예약")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { Task { await load() } } label: { Image(systemName: "arrow.clockwise") }
                }
            }
            .task { await load() }
            .overlay { if loading { ProgressView() } }
        }
    }

    private func row(_ d: [String: Any]) -> some View {
        func s(_ k: String) -> String { (d[k] as? String) ?? "" }
        return VStack(alignment: .leading, spacing: 2) {
            Text("\(s("h_trn_clsf_nm")) \(s("h_trn_no"))").font(.subheadline).bold()
            Text("\(s("h_dpt_rs_stn_nm")) → \(s("h_arv_rs_stn_nm"))")
                .font(.caption).foregroundStyle(.secondary)
            if !s("h_pnr_no").isEmpty {
                Text("PNR \(s("h_pnr_no"))").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func load() async {
        guard app.isLoggedIn else { return }
        loading = true; error = nil
        defer { loading = false }
        do { items = try await app.client.reservations() }
        catch { self.error = error.localizedDescription }
    }
}
