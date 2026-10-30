import Foundation

enum HTTPMethod: String { case get = "GET", post = "POST" }

/// 폼 인코딩 GET/POST + JSON 파싱. 세션 쿠키 유지(로그인 세션).
enum HTTP {
    static let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.httpCookieStorage = HTTPCookieStorage.shared
        c.httpShouldSetCookies = true
        c.httpAdditionalHeaders = ["User-Agent": "Mozilla/5.0 (iPhone; korail4iOS)"]
        c.timeoutIntervalForRequest = 20
        return URLSession(configuration: c)
    }()

    static func request(_ method: HTTPMethod,
                        endpoint: String,
                        params: [String: String]) async throws -> [String: Any] {
        guard var comps = URLComponents(string: Korail.baseURL + Korail.classes + endpoint) else {
            throw KorailError.badURL
        }
        var req: URLRequest
        switch method {
        case .get:
            comps.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
            guard let url = comps.url else { throw KorailError.badURL }
            req = URLRequest(url: url)
        case .post:
            guard let url = comps.url else { throw KorailError.badURL }
            req = URLRequest(url: url)
            req.httpBody = formBody(params)
            req.setValue("application/x-www-form-urlencoded; charset=UTF-8",
                         forHTTPHeaderField: "Content-Type")
        }
        req.httpMethod = method.rawValue
        let (data, _) = try await session.data(for: req)
        return try parseJSON(data)
    }

    private static func formBody(_ params: [String: String]) -> Data {
        params.map { "\(enc($0.key))=\(enc($0.value))" }
              .joined(separator: "&")
              .data(using: .utf8) ?? Data()
    }

    private static func enc(_ s: String) -> String {
        var cs = CharacterSet.alphanumerics
        cs.insert(charactersIn: "-._~")
        return s.addingPercentEncoding(withAllowedCharacters: cs) ?? s
    }

    private static func parseJSON(_ data: Data) throws -> [String: Any] {
        guard var text = String(data: data, encoding: .utf8) else { throw KorailError.decode }
        // 응답이 JSON 앞뒤로 잡음이 붙는 경우 {...} 구간만 추출
        if let a = text.firstIndex(of: "{"), let b = text.lastIndex(of: "}"), a <= b {
            text = String(text[a...b])
        }
        guard let d = text.data(using: .utf8),
              let obj = try JSONSerialization.jsonObject(with: d) as? [String: Any] else {
            throw KorailError.decode
        }
        return obj
    }
}
