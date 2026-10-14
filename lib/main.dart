name: Build APK
on:
  push:
    branches: [ main ]
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with:
          distribution: 'zulu'
          java-version: '17'
      - uses: subosito/flutter-action@v2
        with:
          channel: 'stable'
      - run: flutter clean
      - name: Restore Android if missing
        run: |
          if [! -f "android/app/build.gradle" ]; then
            flutter create. --platforms=android
          fi
      - run: flutter pub get
      - run: dart run flutter_launcher_icons || true
      - name: Build SMALL APK (<15MB)
        run: flutter build apk --release --shrink --split-per-abi --obfuscate --split-debug-info=./symbols --target-platform android-arm64
      - uses: actions/upload-artifact@v4
        with:
          name: flipleaf-small-apk
          path: build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
