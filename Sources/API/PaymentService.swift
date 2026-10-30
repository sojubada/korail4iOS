import Foundation

/// 결제 모듈 (의도적으로 자리만 잡아둠).
///
/// 정책: 앱은 **선점(예약)까지만** 자동화한다. 최종 결제는 코레일 공식앱/웹의
/// 등록 간편결제로 진행한다 — 앱이 카드번호(PAN)를 보관하지 않도록.
///
/// 자동결제(`payment.ReservationPayment`)를 붙이려면:
///  1. 실제 결제 1건의 요청을 관찰해 등록카드/간편결제 식별자 필드를 확정하고
///  2. 카드 과금은 되돌리기 어려우므로, 확정 전에는 구현하지 않는다.
enum PaymentService {
    static func payWithRegisteredMethod(reservation: Reservation) async throws {
        throw KorailError.server(code: nil, message: "앱 내 자동결제는 미구현입니다. 공식앱/웹에서 결제하세요.")
    }
}
