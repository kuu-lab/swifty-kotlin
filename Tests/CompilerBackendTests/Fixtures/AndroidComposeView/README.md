# Android ComposeView counter

AndroidX Compose UI 1.7.8 の `ComposeView` と `AndroidView` で、Snapshot State の変更を
画面に反映するカウンター。kswiftc は実際の Compose Runtime JAR をクラスパスに指定して
`Counter.kt` の `@Composable` 関数をコンパイルする。Java の Activity が
`ComposeView.setContent` から生成された関数に接続し、`AndroidView` の呼び出しも Java を経由する。
Gradle は AndroidX を取得し、Kotlin 標準ライブラリは
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

JVM lowering は通常のトップレベル `@Composable` 関数と、そのモジュール内の呼び出しを対象とする。
既定引数、composable ラムダ、メンバー関数、外部の composable への Kotlin からの直接呼び出しは対象外。
