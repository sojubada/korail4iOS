import Foundation

/// 코레일 모바일 API 상수.
/// 값은 KorailTalk 5.1.1 바이너리에서 추출: `?Device=IP&Version=261028001&Key=korail1234567890`
enum Korail {
    static let baseURL = "https://smart.letskorail.com"
    static let classes = "/classes/"

    static let device = "IP"            // iOS 클라이언트 식별자
    static let version = "261028001"    // 현재 앱 빌드(2026-10-28). 서버가 구버전 차단 시 이 값만 갱신.
    static let defaultKey = "korail1234567890"  // 로그인 성공 시 서버가 내려주는 Key로 교체됨

    enum EP {
        static let code          = "com.korail.mobile.common.code.do"
        static let login         = "com.korail.mobile.login.Login"
        static let logout        = "com.korail.mobile.login.Logout"
        static let stationData   = "com.korail.mobile.common.stationdata"
        static let schedule      = "com.korail.mobile.seatMovie.ScheduleView"
        static let residualSeats = "com.korail.mobile.lms.TResidualSeatsResearch.do"
        static let reserve       = "com.korail.mobile.certification.TicketReservation"
        static let reservations  = "com.korail.mobile.reservation.ReservationView"
        static let myTickets     = "com.korail.mobile.myTicket.MyTicketList"
        static let priceView     = "com.korail.mobile.payment.TicketPriceView"
        static let payment       = "com.korail.mobile.payment.ReservationPayment"
        static let cancel        = "com.korail.mobile.reservationCancel.ReservationCancel"
    }

    /// 열차 종별 (selGoTrain / txtTrnGpCd)
    enum TrainType: String, CaseIterable, Identifiable {
        case all = "05"       // 전체
        case ktx = "100"      // KTX/KTX-산천/이음
        case saemaul = "101"
        case mugunghwa = "102"
        var id: String { rawValue }
        var label: String {
            switch self {
            case .all: return "전체"; case .ktx: return "KTX"
            case .saemaul: return "새마을"; case .mugunghwa: return "무궁화"
            }
        }
    }
}
