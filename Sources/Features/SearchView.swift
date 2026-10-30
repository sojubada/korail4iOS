import SwiftUI

struct SearchQuery {
    let depCode, depName, arrCode, arrName: String
    let date: Date
    let trainType: Korail.TrainType
    let adults: Int

    var dateStr: String { Self.fmt("yyyyMMdd", date) }
    var timeStr: String { Self.fmt("HHmmss", date) }
    private static func fmt(_ f: String, _ d: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = f
        df.locale = Locale(identifier: "ko_KR")
        return df.string(from: d)
    }
}

struct SearchView: View {
    @EnvironmentObject var app: AppState
    @AppStorage("depCode") private var depCode = ""
    @AppStorage("depName") private var depName = ""
    @AppStorage("arrCode") private var arrCode = ""
    @AppStorage("arrName") private var arrName = ""
    @AppStorage("adults") private var adults = 1
    @State private var date = Date()
    @State private var trainType: Korail.TrainType = .all
    @State private var seat: SeatClass = .general
    @State private var pickingDep = false
    @State private var pickingArr = false

    var body: some View {
        NavigationStack {
            Form {
                Section("구간") {
                    stationRow(title: "출발", name: depName) { pickingDep = true }
                    stationRow(title: "도착", name: arrName) { pickingArr = true }
                    Button { swapStations() } label: {
                        Label("출발 ↔ 도착", systemImage: "arrow.up.arrow.down")
                    }
                }
                Section("일시") {
                    DatePicker("출발", selection: $date, in: Date()...,
                               displayedComponents: [.date, .hourAndMinute])
                        .environment(\.locale, Locale(identifier: "ko_KR"))
                }
                Section("옵션") {
                    Picker("열차", selection: $trainType) {
                        ForEach(Korail.TrainType.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("좌석", selection: $seat) {
                        ForEach(SeatClass.allCases) { Text($0.label).tag($0) }
                    }
                    Stepper("어른 \(adults)명", value: $adults, in: 1...9)
                }
                NavigationLink {
                    ResultsView(query: currentQuery, seat: seat)
                } label: {
                    Label("조회", systemImage: "magnifyingglass")
                }
                .disabled(depCode.isEmpty || arrCode.isEmpty)
            }
            .navigationTitle("조회·예약")
            .sheet(isPresented: $pickingDep) {
                StationPicker(title: "출발역") { depCode = $0.code; depName = $0.name }
            }
            .sheet(isPresented: $pickingArr) {
                StationPicker(title: "도착역") { arrCode = $0.code; arrName = $0.name }
            }
            .safeAreaInset(edge: .bottom) {
                if let b = app.banner {
                    Text(b).font(.footnote).padding(8)
                        .background(.thinMaterial).clipShape(Capsule()).padding(.bottom, 6)
                }
            }
        }
    }

    private var currentQuery: SearchQuery {
        SearchQuery(depCode: depCode, depName: depName,
                    arrCode: arrCode, arrName: arrName,
                    date: date, trainType: trainType, adults: adults)
    }

    private func stationRow(title: String, name: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                Text(name.isEmpty ? "선택" : name)
                    .foregroundStyle(name.isEmpty ? Color.secondary : Color.primary)
            }
        }
        .tint(.primary)
    }

    private func swapStations() {
        let c = depCode, n = depName
        depCode = arrCode; depName = arrName
        arrCode = c; arrName = n
    }
}

struct StationPicker: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    let title: String
    let onPick: (Station) -> Void
    @State private var q = ""
    @State private var manualCode = ""

    var body: some View {
        NavigationStack {
            List {
                if app.stations.isEmpty {
                    Section("역 목록을 불러오지 못했습니다 — 코드 직접 입력") {
                        TextField("역 코드 (예: 0104)", text: $manualCode)
                            .keyboardType(.numberPad)
                        Button("사용") {
                            guard !manualCode.isEmpty else { return }
                            onPick(Station(code: manualCode, name: manualCode)); dismiss()
                        }
                    }
                } else {
                    ForEach(filtered) { s in
                        Button(s.name) { onPick(s); dismiss() }
                    }
                }
            }
            .searchable(text: $q, prompt: "역 이름")
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } }
            }
        }
    }

    private var filtered: [Station] {
        q.isEmpty ? app.stations : app.stations.filter { $0.name.contains(q) }
    }
}
