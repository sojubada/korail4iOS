import Foundation
import CommonCrypto

/// 로그인 비밀번호 암호화.
/// 코레일 공식 앱과 동일: 서버가 내려준 key로 AES-CBC 암호화(IV = key 앞 16바이트, PKCS7),
/// 그 결과를 base64로 **두 번** 인코딩.
enum AESCipher {
    static func encryptDoubleBase64(password: String, keyString: String) throws -> String {
        let keyBytes = Array(keyString.utf8)
        let ivBytes = Array(keyString.prefix(16).utf8)
        guard keyBytes.count == kCCKeySizeAES128 || keyBytes.count == kCCKeySizeAES192
                || keyBytes.count == kCCKeySizeAES256, ivBytes.count == kCCBlockSizeAES128 else {
            throw KorailError.crypto
        }
        let input = Array(password.utf8)
        var output = [UInt8](repeating: 0, count: input.count + kCCBlockSizeAES128)
        var moved = 0
        let status = CCCrypt(
            CCOperation(kCCEncrypt),
            CCAlgorithm(kCCAlgorithmAES),
            CCOptions(kCCOptionPKCS7Padding),
            keyBytes, keyBytes.count,
            ivBytes,
            input, input.count,
            &output, output.count,
            &moved
        )
        guard status == kCCSuccess else { throw KorailError.crypto }
        let cipher = Data(output.prefix(moved))
        let inner = cipher.base64EncodedString()               // 1차 base64
        return Data(inner.utf8).base64EncodedString()           // 2차 base64
    }
}
