import Foundation

enum KorailError: LocalizedError {
    case badURL, decode, crypto, notLoggedIn
    case server(code: String?, message: String?)

    var errorDescription: String? {
        switch self {
        case .badURL:       return "잘못된 URL"
        case .decode:       return "응답 파싱 실패"
        case .crypto:       return "비밀번호 암호화 실패"
        case .notLoggedIn:  return "로그인이 필요합니다"
        case .server(let c, let m):
            let code = (c?.isEmpty == false) ? "[\(c!)] " : ""
            return "\(code)\(m ?? "서버 오류")"
        }
    }
}

enum LoginIDType: String, CaseIterable, Identifiable {
    case membership = "2"   // 멤버십 번호
    case phone      = "4"   // 휴대폰 번호
    case email      = "5"   // 이메일
    var id: String { rawValue }
    var label: String {
        switch self {
        case .membership: return "멤버십번호"
        case .phone:      return "휴대폰"
        case .email:      return "이메일"
        }
    }
}

enum SeatClass: String, CaseIterable, Identifiable {
    case general = "1"   // 일반실
    case special = "2"   // 특실
    var id: String { rawValue }
    var label: String { self == .general ? "일반실" : "특실" }
}

struct Station: Identifiable, Hashable {
    let code: String
    let name: String
    var id: String { code }
}

struct Member {
    let key: String
    let membershipNo: String
    let name: String
    let email: String
}

struct Train: Identifiable, Hashable {
    let trainType: String       // h_trn_clsf_cd
    let trainTypeName: String   // h_trn_clsf_nm
    let trainGroup: String      // h_trn_gp_cd
    let trainNo: String         // h_trn_no
    let depName: String, depCode: String
    let arrName: String, arrCode: String
    let depDate: String, depTime: String   // yyyyMMdd / HHmmss
    let arrDate: String, arrTime: String
    let runDate: String         // h_run_dt
    let generalSeatCode: String // h_gen_rsv_cd
    let specialSeatCode: String // h_spe_rsv_cd
    let reserveFlag: String     // h_rsv_psb_flg

    var id: String { trainNo + depDate + depTime }
    var hasGeneralSeat: Bool { generalSeatCode == "11" }   // '11' = 여유
    var hasSpecialSeat: Bool { specialSeatCode == "11" }
    var isReservable: Bool { reserveFlag == "Y" || hasGeneralSeat || hasSpecialSeat }

    var depTimeShort: String { Self.hhmm(depTime) }
    var arrTimeShort: String { Self.hhmm(arrTime) }
    private static func hhmm(_ t: String) -> String {
        guard t.count >= 4 else { return t }
        let h = t.prefix(2), m = t.dropFirst(2).prefix(2)
        return "\(h):\(m)"
    }

    init?(_ j: [String: Any]) {
        func s(_ k: String) -> String { (j[k] as? String) ?? "" }
        guard !s("h_trn_no").isEmpty else { return nil }
        trainType = s("h_trn_clsf_cd");  trainTypeName = s("h_trn_clsf_nm")
        trainGroup = s("h_trn_gp_cd");   trainNo = s("h_trn_no")
        depName = s("h_dpt_rs_stn_nm");  depCode = s("h_dpt_rs_stn_cd")
        arrName = s("h_arv_rs_stn_nm");  arrCode = s("h_arv_rs_stn_cd")
        depDate = s("h_dpt_dt");         depTime = s("h_dpt_tm")
        arrDate = s("h_arv_dt");         arrTime = s("h_arv_tm")
        runDate = s("h_run_dt")
        generalSeatCode = s("h_gen_rsv_cd"); specialSeatCode = s("h_spe_rsv_cd")
        reserveFlag = s("h_rsv_psb_flg")
    }
}

struct Reservation: Identifiable {
    let pnrNo: String
    let journeyNo: String
    let totalPrice: Int
    let raw: [String: Any]
    var id: String { pnrNo + journeyNo }
}
