import Foundation

/// 코레일 모바일 API 클라이언트. 로그인 → 조회 → 선점(예약).
@MainActor
final class KorailClient {
    private(set) var key = Korail.defaultKey
    private(set) var member: Member?
    var isLoggedIn: Bool { member != nil }

    // MARK: 공통
    private func common(_ extra: [String: String] = [:]) -> [String: String] {
        var p: [String: String] = ["Device": Korail.device, "Version": Korail.version]
        extra.forEach { p[$0] = $1 }
        return p
    }

    private func checkResult(_ j: [String: Any]) throws {
        if (j["strResult"] as? String) == "FAIL" {
            throw KorailError.server(code: j["h_msg_cd"] as? String,
                                     message: j["h_msg_txt"] as? String)
        }
    }

    // MARK: 로그인
    func login(id: String, password: String, idType: LoginIDType) async throws {
        // 1) 암호화 키/idx 수신
        let codeResp = try await HTTP.request(.post, endpoint: Korail.EP.code,
                                              params: ["code": "app.login.cphd"])
        guard let cphd = codeResp["app.login.cphd"] as? [String: Any],
              let srvKey = cphd["key"] as? String,
              let idx = cphd["idx"] as? String else {
            throw KorailError.server(code: nil, message: "로그인 키 수신 실패")
        }
        let encPw = try AESCipher.encryptDoubleBase64(password: password, keyString: srvKey)

        // 2) 로그인
        let p = common([
            "txtInputFlg": idType.rawValue,
            "txtMemberNo": id,
            "txtPwd": encPw,
            "idx": idx
        ])
        let j = try await HTTP.request(.post, endpoint: Korail.EP.login, params: p)
        try checkResult(j)
        guard (j["strResult"] as? String) == "SUCC",
              let mbNo = j["strMbCrdNo"] as? String else {
            throw KorailError.server(code: j["h_msg_cd"] as? String,
                                     message: (j["h_msg_txt"] as? String) ?? "로그인 실패")
        }
        key = (j["Key"] as? String) ?? key
        member = Member(key: key, membershipNo: mbNo,
                        name: (j["strCustNm"] as? String) ?? "",
                        email: (j["strEmailAdr"] as? String) ?? "")
    }

    func logout() async {
        _ = try? await HTTP.request(.get, endpoint: Korail.EP.logout, params: common())
        member = nil
        key = Korail.defaultKey
    }

    // MARK: 역 목록 (런타임 수신, 하드코딩 안 함)
    func stations() async throws -> [Station] {
        let j = try await HTTP.request(.get, endpoint: Korail.EP.stationData, params: common())
        // 응답 스키마가 유동적이라 흔한 형태들을 방어적으로 탐색
        let candidates: [[String: Any]] =
            (((j["stns"] as? [String: Any])?["stn"]) as? [[String: Any]])
            ?? (j["stn"] as? [[String: Any]])
            ?? (((j["station_infos"] as? [String: Any])?["station_info"]) as? [[String: Any]])
            ?? []
        let stations = candidates.compactMap { d -> Station? in
            let name = (d["stn_nm"] as? String) ?? (d["h_stn_nm"] as? String)
            let code = (d["stn_cd"] as? String) ?? (d["h_stn_cd"] as? String)
            guard let n = name, let c = code, !n.isEmpty, !c.isEmpty else { return nil }
            return Station(code: c, name: n)
        }
        return stations.sorted { $0.name < $1.name }
    }

    // MARK: 열차 조회
    func search(depCode: String, arrCode: String,
                date: String, time: String,
                trainType: Korail.TrainType = .all,
                adults: Int = 1) async throws -> [Train] {
        let p = common([
            "radJobId": "1",
            "selGoTrain": trainType.rawValue,
            "txtCardPsgCnt": "0",
            "txtGdNo": "",
            "txtGoAbrdDt": date,          // yyyyMMdd
            "txtGoStart": depCode,
            "txtGoEnd": arrCode,
            "txtGoHour": time,            // HHmmss
            "txtJobDv": "",
            "txtMenuId": "11",
            "txtPsgFlg_1": String(adults), // 어른
            "txtPsgFlg_2": "0",            // 어린이
            "txtPsgFlg_3": "0",            // 경로
            "txtPsgFlg_4": "0",
            "txtPsgFlg_5": "0",
            "txtPsgFlg_8": "0",            // 유아
            "txtSeatAttCd_2": "000",
            "txtSeatAttCd_3": "000",
            "txtSeatAttCd_4": "015",
            "txtTrnGpCd": trainType.rawValue
        ])
        let j = try await HTTP.request(.get, endpoint: Korail.EP.schedule, params: p)
        try checkResult(j)
        let infos = (j["trn_infos"] as? [String: Any])?["trn_info"]
        let list: [[String: Any]]
        if let a = infos as? [[String: Any]] { list = a }
        else if let one = infos as? [String: Any] { list = [one] }
        else { list = [] }
        return list.compactMap { Train($0) }
    }

    // MARK: 예약(선점)
    @discardableResult
    func reserve(train t: Train, seat: SeatClass = .general, adults: Int = 1) async throws -> Reservation {
        guard isLoggedIn else { throw KorailError.notLoggedIn }
        var p = common([
            "Key": key,
            "txtGdNo": "",
            "txtJobId": "1101",           // 1101: 좌석지정예약
            "txtTotPsgCnt": String(adults),
            "txtSeatAttCd1": "000", "txtSeatAttCd2": "000", "txtSeatAttCd3": "000",
            "txtSeatAttCd4": "015", "txtSeatAttCd5": "000",
            "hidFreeFlg": "N", "txtStndFlg": "N",
            "txtMenuId": "11", "txtSrcarCnt": "0", "txtJrnyCnt": "1",
            // 여정 1
            "txtJrnySqno1": "001", "txtJrnyTpCd1": "11",
            "txtDptDt1": t.depDate, "txtDptRsStnCd1": t.depCode, "txtDptTm1": t.depTime,
            "txtArvRsStnCd1": t.arrCode, "txtTrnNo1": t.trainNo, "txtRunDt1": t.runDate,
            "txtTrnClsfCd1": t.trainType, "txtPsrmClCd1": seat.rawValue, "txtTrnGpCd1": t.trainGroup,
            "txtChgFlg1": "",
            // 여정 2 (미사용)
            "txtJrnySqno2": "", "txtJrnyTpCd2": "", "txtDptDt2": "", "txtDptRsStnCd2": "",
            "txtDptTm2": "", "txtArvRsStnCd2": "", "txtTrnNo2": "", "txtRunDt2": "",
            "txtTrnClsfCd2": "", "txtChgFlg2": ""
        ])
        // 승객: 어른(txtPsgTpCd=1), 할인없음(000)
        for i in 1...adults {
            p["txtPsgTpCd\(i)"] = "1"
            p["txtDiscKndCd\(i)"] = "000"
            p["txtCompaCnt\(i)"] = "1"
            p["txtCardCode_\(i)"] = ""
            p["txtCardNo_\(i)"] = ""
            p["txtCardPw_\(i)"] = ""
        }
        let j = try await HTTP.request(.get, endpoint: Korail.EP.reserve, params: p)
        try checkResult(j)
        let pnr = (j["h_pnr_no"] as? String) ?? (j["pnr_no"] as? String) ?? ""
        let price = Int((j["h_tot_rcvd_amt"] as? String) ?? (j["h_rcvd_amt"] as? String) ?? "") ?? 0
        return Reservation(pnrNo: pnr,
                           journeyNo: (j["h_jrny_sqno"] as? String) ?? "001",
                           totalPrice: price, raw: j)
    }

    // MARK: 예약 목록
    func reservations() async throws -> [[String: Any]] {
        guard isLoggedIn else { throw KorailError.notLoggedIn }
        let j = try await HTTP.request(.get, endpoint: Korail.EP.reservations, params: common(["Key": key]))
        try checkResult(j)
        return ((j["jrny_infos"] as? [String: Any])?["jrny_info"] as? [[String: Any]]) ?? []
    }
}
