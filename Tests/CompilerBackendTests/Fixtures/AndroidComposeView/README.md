# Android ComposeView counter

AndroidX Compose UI 1.7.8 の `ComposeView` と `AndroidView` で、Snapshot State の変更を
画面に反映するカウンター。Gradle は AndroidX を取得し、Kotlin 標準ライブラリは
`kswiftc --stdlib-only` でこのリポジトリから生成する。

Android SDK 36.1、Build Tools 36.1.0、Gradle 9.8、JDK を用意し、リポジトリのルートで実行する。
起動後に **Increment** を押すと `Compose count: 0` が `Compose count: 1` に変わる。

```bash
bash Scripts/swift_build.sh --product kswiftc
app=Tests/CompilerBackendTests/Fixtures/AndroidComposeView
bash "$app/build.sh"
adb install -r "$app/build/outputs/apk/debug/ComposeProbe-debug.apk"
adb shell am start -n org.swiftykotlin.composeprobe/.MainActivity
```
