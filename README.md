# korail4iOS

개인용 코레일(KTX/일반열차) 예약 iOS 앱. 코레일톡이 TrollStore 환경(또는 기타 사유)에서 실행이 막힐 때, **본인 코레일 계정으로 직접 서버 API를 호출**해 조회·예약하기 위한 가벼운 클라이언트입니다.

> ⚠️ **개인 사용 전용.** 본인 계정으로 **본인이 탈 승차권**을 예매하는 용도로만 사용하세요.
> - 자동 매크로로 표를 대량 선점하거나 취소표를 고속으로 긁는 행위, 되팔이(암표)는 **하지 마세요.** 코레일 이용약관 위반이며, 코레일은 이를 추적·제재합니다(앱 바이너리에도 `crime/Scalper` 신고 경로가 존재).
> - 비공식 클라이언트 접속 자체가 코레일 약관에 저촉될 수 있습니다. 책임은 사용자에게 있습니다.
> - 배포용이 아닙니다.

## 상태

| 기능 | 상태 |
|---|---|
| 자동 로그인 (Keychain 저장) | ✅ |
| 역 목록 (서버에서 런타임 수신) | ✅ |
| 열차 조회 (ScheduleView) | ✅ |
| 좌석 여유 표시 (일반/특실) | ✅ |
| 좌석 새로고침 (수동 + 안전 간격 반자동) | ✅ |
| 예약(선점) TicketReservation | ✅ |
| 예약 목록 | ✅ |
| **결제** | ⚠️ 선점까지만. 최종 결제는 코레일 공식앱/웹의 등록 간편결제로 (아래 "결제 설계" 참고) |

## 보안 설계 (중요)

- **카드번호 원문을 앱에 저장하지 않습니다.** 로그인 자격증명만 iOS Keychain(`WhenUnlockedThisDeviceOnly`)에 저장합니다.
- 결제는 **선점(예약) → 코레일에 이미 등록된 간편결제로 결제** 하는 흐름을 권장합니다. 앱이 PAN(카드번호)·비밀번호를 들고 있지 않도록 설계했습니다.
- 로그인 비밀번호는 코레일 서버가 내려준 키로 **AES-CBC 암호화 후 전송**합니다(공식 앱과 동일 방식).

## 빌드 & 설치 (맥 + TrollStore)

사전 준비: macOS, Xcode, [XcodeGen](https://github.com/yonaskolb/XcodeGen), 기기에 TrollStore.

```bash
brew install xcodegen
cd korail4iOS
xcodegen generate          # project.yml -> korail4iOS.xcodeproj 생성
open korail4iOS.xcodeproj
```

Xcode에서 서명 없이 빌드 → 미서명 `.app`을 IPA로 포장 → TrollStore로 설치:

```bash
# 빌드 산출물(.app)을 Payload/ 에 넣어 IPA 생성 (서명 불필요: TrollStore가 ldid로 서명)
mkdir -p build/Payload
cp -R "$(xcodebuild -showBuildSettings | awk '/CODESIGNING_FOLDER_PATH/{print $3}')" build/Payload/
cd build && zip -r korail4iOS.tipa Payload
# korail4iOS.tipa 를 기기로 옮겨 TrollStore에서 열기
```

> `project.yml`에 `CODE_SIGNING_ALLOWED: NO`로 설정돼 있어 미서명 빌드가 나옵니다. TrollStore가 설치 시 서명합니다.

## 버전 헤더 유지보수

코레일 서버는 요청의 `Version` 값으로 구버전을 막습니다. 현재 값은 `Sources/API/KorailConstants.swift`의 `version = "261028001"`. 서버가 버전을 올려 조회가 막히면, 최신 코레일톡의 빌드 버전으로 이 상수만 갱신하면 됩니다.

## 구조

```
Sources/
  App/        앱 진입점, 전역 상태
  API/        KorailClient(로그인/조회/예약), 모델, 암호화, HTTP, 결제
  Store/      Keychain 자격증명, 앱 설정
  Features/   로그인/조회/결과/예약/내티켓 화면
```

## 결제 설계 (현재/다음 단계)

현재는 **선점까지** 자동화하고, 결제 화면은 예약 상세와 함께 "공식앱/웹에서 등록 간편결제로 결제" 안내를 띄웁니다. 앱 내 자동결제(`payment.ReservationPayment`)를 붙이려면 그 엔드포인트의 정확한 파라미터(등록카드 토큰·간편결제 식별자)를 실제 결제 1건의 요청을 관찰해 확정해야 합니다 — 카드 과금은 실수 시 피해가 커서, 파라미터가 확인되기 전엔 자동결제를 구현하지 않습니다. `Sources/API/PaymentService.swift`에 자리를 잡아뒀습니다.
