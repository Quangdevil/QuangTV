# Build QuangTV trên Mac Apple Silicon

Nguồn ứng dụng lấy từ `tv-viewer-app/tv_viewer` tại commit `188df516a8acb4a2fda0d65fed8b6199c734603f`; các override trong repository này được áp dụng vào checkout riêng `upstream`. Không dùng bản APK tải lại từ trang tổng hợp.

## Công cụ

- Flutter **3.44.4**, cùng phiên bản với GitHub Actions.
- JDK 17, Android SDK platform 36, Build Tools 35.0.0, NDK 28.2.13676358.
- Git, Python 3, Node.js, curl; Android SDK licenses đã được chấp nhận trên máy build.
- Công cụ trên Mac hiện tại nằm tại `~/.local/share/autodev`; có thể đổi bằng `AUTODEV_TOOLS`, `FLUTTER_BIN`, `JAVA_HOME`, `ANDROID_HOME`.

## Bản kiểm thử local

```sh
bash scripts/build_macos.sh --qa
```

Lệnh chuẩn bị nguồn, patch VLC riêng cho từng FlutterEngine, kiểm tra checksum Gradle, chạy phân tích Dart và các kiểm thử nguồn VTV, proxy, Cloudflare và chứng chỉ, rồi build APK ARM64 release có R8. Kết quả và log ở `.local-build`.

Bản QA dùng package `com.quangduren.quangtv.localqa`, nhãn **QuangTV Local QA** và khóa debug. Có thể cài song song với QuangTV; bản này không phải bản OTA sản xuất. Script không đổi khóa ký của package sản xuất.

Nếu recipe đã thay đổi sau lần chuẩn bị trước, giữ lại hoặc di chuyển `upstream` và `.local-build/prepared-source` rồi chạy lại để lấy một checkout mới. Script từ chối ghi đè mã nguồn đã sửa mà chưa có dấu chuẩn bị hợp lệ.

## Bản phát hành

```sh
BUILD_NUMBER=NUMBER_ABOVE_CURRENT_OTA bash scripts/build_macos.sh --release
```

Cần `upstream/flutter_app/android/key.properties` và keystore lâu dài tương ứng. Chúng bị loại khỏi Git. Không tạo khóa mới để thay thế khóa của bản đã phát hành. GitHub Actions tiếp tục sử dụng các signing secret sẵn có và giữ nguyên các cổng kiểm thử trước khi phát hành OTA.

Lệnh build local xác minh cấu trúc APK và chữ ký; kiểm thử widget và nguồn giả lập không xác nhận mọi stream trên internet hoặc thiết bị thật đều phát được.

## iOS

Recipe hiện tại tích hợp native Android, chưa cung cấp bản iOS. Cài Xcode hoặc chạy `flutter build ipa` không tự chuyển các channel Android sang iOS. Việc xuất IPA cần thực hiện phần iOS riêng và ký bằng tài khoản/chứng chỉ phù hợp. Máy hiện tại chưa có Xcode đầy đủ; tải Xcode tương thích qua Apple Developer yêu cầu Apple ID, và cài đặt qua App Store yêu cầu xác thực quản trị.
