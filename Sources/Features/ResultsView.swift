import SwiftUI

struct ResultsView: View {
    @EnvironmentObject var app: AppState
    let query: SearchQuery
    let seat: SeatClass
    @StateObject private var vm = ResultsVM()

    var body: some View {
        List {
            if let e = vm.error {
                Text(e).foregroundStyle(.red).font(.footnote)
            }
            ForEach(vm.trains) { t in
                TrainRow(train: t, seat: seat, reserving: vm.reservingID == t.id) {
                    Task { await vm.reserve(t, seat: seat, app: app) }
                }
            }
            if vm.trains.isEmpty && !vm.loading && vm.error == nil {
                Text("조회 결과가 없습니다.").foregroundStyle(.secondary)
            }
        }
        .navigationTitle("\(query.depName) → \(query.arrName)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Toggle(isOn: $vm.auto) { Image(systemName: "timer") }
                    .toggleStyle(.button)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { Task { await vm.refresh(query: query, app: app) } } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        .refreshable { await vm.refresh(query: query, app: app) }
        .overlay {
            if vm.loading && vm.trains.isEmpty { ProgressView() }
        }
        .task { await vm.refresh(query: query, app: app) }
        .onChange(of: vm.auto) { on in vm.setAuto(on, query: query, app: app) }
        .onDisappear { vm.stopAuto() }
        .sheet(item: $vm.reservation) { r in
            ReserveResultView(reservation: r, train: vm.lastReservedTrain)
        }
        .safeAreaInset(edge: .bottom) {
            if vm.auto {
                Text("자동 새로고침 \(ResultsVM.minInterval)초 간격 — 여유 좌석이 뜨면 '예약'을 누르세요")
                    .font(.caption2).foregroundStyle(.secondary).padding(.bottom, 6)
            }
        }
    }
}

@MainActor
final class ResultsVM: ObservableObject {
    @Published var trains: [Train] = []
    @Published var loading = false
    @Published var error: String?
    @Published var reservingID: String?
    @Published var reservation: Reservation?
    @Published var auto = false
    var lastReservedTrain: Train?

    /// 서버 과부하·매크로 방지를 위한 자동 새로고침 최소 간격(초).
    /// 개인용 1건 예매 목적을 넘어서는 고속 폴링을 막기 위한 하한선.
    static let minInterval: UInt64 = 15
    private var task: Task<Void, Never>?

    func refresh(query: SearchQuery, app: AppState) async {
        loading = true; error = nil
        defer { loading = false }
        do {
            trains = try await app.client.search(
                depCode: query.depCode, arrCode: query.arrCode,
                date: query.dateStr, time: query.timeStr,
                trainType: query.trainType, adults: query.adults)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func reserve(_ t: Train, seat: SeatClass, app: AppState) async {
        guard app.isLoggedIn else { error = "예약하려면 로그인하세요 (계정 탭)"; return }
        reservingID = t.id
        defer { reservingID = nil }
        do {
            let r = try await app.client.reserve(train: t, seat: seat, adults: 1)
            lastReservedTrain = t
            reservation = r
            auto = false; stopAuto()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func setAuto(_ on: Bool, query: SearchQuery, app: AppState) {
        on ? startAuto(query: query, app: app) : stopAuto()
    }

    private func startAuto(query: SearchQuery, app: AppState) {
        stopAuto()
        task = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.refresh(query: query, app: app)
                try? await Task.sleep(nanoseconds: Self.minInterval * 1_000_000_000)
            }
        }
    }

    func stopAuto() { task?.cancel(); task = nil }
}

struct TrainRow: View {
    let train: Train
    let seat: SeatClass
    let reserving: Bool
    let onReserve: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(train.trainTypeName) \(train.trainNo)").font(.subheadline).bold()
                Text("\(train.depTimeShort) → \(train.arrTimeShort)")
                    .font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    badge("일반", train.hasGeneralSeat)
                    badge("특실", train.hasSpecialSeat)
                }
            }
            Spacer()
            Button(action: onReserve) {
                if reserving { ProgressView() } else { Text("예약") }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!available || reserving)
        }
        .padding(.vertical, 2)
    }

    private var available: Bool {
        seat == .special ? train.hasSpecialSeat : train.hasGeneralSeat
    }

    private func badge(_ t: String, _ ok: Bool) -> some View {
        Text(t)
            .font(.caption2)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(ok ? Color.green.opacity(0.22) : Color.gray.opacity(0.15))
            .foregroundStyle(ok ? Color.green : Color.secondary)
            .clipShape(Capsule())
    }
}
