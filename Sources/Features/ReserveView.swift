import SwiftUI

struct ReserveResultView: View {
    @Environment(\.dismiss) private var dismiss
    let reservation: Reservation
    let train: Train?

    var body: some View {
        NavigationStack {
            List {
                Section("선점 완료") {
                    if let t = train {
                        LabeledContent("열차", value: "\(t.trainTypeName) \(t.trainNo)")
                        LabeledContent("구간", value: "\(t.depName) → \(t.arrName)")
                        LabeledContent("시간", value: "\(t.depTimeShort) → \(t.arrTimeShort)")
                    }
                    if !reservation.pnrNo.isEmpty {
                        LabeledContent("예약번호(PNR)", value: reservation.pnrNo)
                    }
                    if reservation.totalPrice > 0 {
                        LabeledContent("금액", value: "\(reservation.totalPrice)원")
                    }
                }
                Section("결제") {
                    Text("좌석이 약 10~20분간 선점되었습니다. 시간 내 결제하지 않으면 자동 취소됩니다.")
                        .font(.footnote)
                    Text("결제는 코레일 공식앱/웹에서 등록된 간편결제로 완료하세요.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if let url = URL(string: "https://www.korail.com/ticket/login") {
                        Link("코레일 웹에서 결제하기", destination: url)
                    }
                }
            }
            .navigationTitle("예약")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("완료") { dismiss() } }
            }
        }
    }
}
