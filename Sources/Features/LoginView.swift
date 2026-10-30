import SwiftUI

struct AccountView: View {
    @EnvironmentObject var app: AppState
    var body: some View {
        NavigationStack {
            if app.isLoggedIn { loggedIn } else { LoginForm() }
        }
    }

    private var loggedIn: some View {
        List {
            Section("로그인됨") {
                LabeledContent("이름", value: app.member?.name ?? "")
                LabeledContent("멤버십", value: app.member?.membershipNo ?? "")
            }
            Section {
                Button("로그아웃") { Task { await app.logout() } }
                Button("저장된 자격증명 삭제", role: .destructive) { app.forget() }
            }
            Section {
                Text("본인 계정으로 본인 승차권 예매 전용입니다. 자동 매크로·대량선점·되팔이는 하지 마세요.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("계정")
    }
}

struct LoginForm: View {
    @EnvironmentObject var app: AppState
    @State private var idType: LoginIDType = .membership
    @State private var id = ""
    @State private var pw = ""
    @State private var remember = true
    @State private var busy = false
    @State private var err: String?

    var body: some View {
        Form {
            Picker("로그인 방식", selection: $idType) {
                ForEach(LoginIDType.allCases) { Text($0.label).tag($0) }
            }
            TextField(idType.label, text: $id)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(idType == .email ? .emailAddress : .numberPad)
            SecureField("비밀번호", text: $pw)
            Toggle("자동 로그인(기기에 저장)", isOn: $remember)
            if let err { Text(err).foregroundStyle(.red).font(.footnote) }
            Button {
                Task { await doLogin() }
            } label: {
                if busy { ProgressView() } else { Text("로그인") }
            }
            .disabled(busy || id.isEmpty || pw.isEmpty)
        }
        .navigationTitle("코레일 로그인")
    }

    private func doLogin() async {
        busy = true; err = nil
        defer { busy = false }
        do { try await app.login(id: id, password: pw, idType: idType, remember: remember) }
        catch { err = error.localizedDescription }
    }
}
