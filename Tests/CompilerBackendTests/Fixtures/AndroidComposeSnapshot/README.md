# Android Compose Snapshot counter

Jetpack Compose Runtime 1.7.8 の `MutableState` と `SnapshotStateObserver` で
カウントの変更を Android の画面に反映する。`MainActivity.kt` は kswiftc で
コンパイルし、Java の `ComposeCounterState` が AndroidX Runtime に接続する。
表示には Android Views を使う。APK の Kotlin 標準ライブラリは
`kswiftc --stdlib-only` でこのリポジトリから生成する。

Android SDK 36.1、Build Tools 36.1.0、Gradle 9.8、JDK、Python 3 を用意する。
リポジトリのルートで以下を実行し、起動後に **Increment** を押すと
`Compose count: 0` が `Compose count: 1` に変わる。

```bash
bash Scripts/swift_build.sh --product kswiftc
app=Tests/CompilerBackendTests/Fixtures/AndroidComposeSnapshot
bash "$app/build.sh"
adb install -r "$app/build/outputs/apk/debug/ComposeProbe-debug.apk"
adb shell am start -n org.swiftykotlin.composeprobe/.MainActivity
```
