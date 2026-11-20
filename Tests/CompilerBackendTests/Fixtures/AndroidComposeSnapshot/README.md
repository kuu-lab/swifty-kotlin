# Android Compose Snapshot counter

Jetpack Compose Runtime 1.7.8 の `MutableState` と `SnapshotStateObserver` で
カウントの変更を Android の画面に反映する。`MainActivity.kt` と、AndroidX Runtime に
接続する Java の `ComposeCounterState` を kswiftc だけでビルドする。表示には
Android Views を使う。

kswiftc が Compose Runtime とその依存を Google Maven / Maven Central から解決し、
Java ソースを javac でコンパイルしたうえで、ライブラリの manifest をマージして
dex 化・署名まで行う。Gradle は使わない。APK には `-include-runtime` で
このリポジトリの Kotlin 標準ライブラリを同梱する。

Android SDK 36.1、Build Tools 36.1.0、JDK を用意する。リポジトリのルートで以下を
実行し、起動後に **Increment** を押すと `Compose count: 0` が `Compose count: 1` に変わる。

```bash
bash Scripts/swift_build.sh --product kswiftc
app=Tests/CompilerBackendTests/Fixtures/AndroidComposeSnapshot
bash "$app/build.sh"
adb install -r "$app/build/outputs/apk/debug/ComposeProbe-debug.apk"
adb shell am start -n org.swiftykotlin.composeprobe/.MainActivity
```

ダウンロードした依存は `~/.kswiftk/maven` にキャッシュされる。2 回目以降は
`bash "$app/build.sh" --offline` でネットワークなしでもビルドできる。
