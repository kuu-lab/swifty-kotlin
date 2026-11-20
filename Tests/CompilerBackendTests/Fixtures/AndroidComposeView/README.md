# Kotlin Android Compose task list

`MainActivity.kt` を kswiftc でコンパイルする。Material 3 の `OutlinedTextField` と
`Button` でタスクを追加し、Compose Foundation の `LazyColumn` に表示する。入力と
タスク一覧は `mutableStateOf` で保持し、追加時に入力欄を空にして一覧を再コンポジションする。

kswiftc が AndroidX Compose 1.7.8 と Compose Material 3 1.3.2 の依存閉包（約 50 モジュール）を
Google Maven / Maven Central から解決する。そのうえでライブラリのリソースと manifest をマージし、
dex 化・署名まで行う。Gradle は使わない。APK には `-include-runtime` で
このリポジトリの Kotlin 標準ライブラリを同梱する。

Android SDK 36.1、Build Tools 36.1.0、JDK を用意し、リポジトリのルートで実行する。
起動すると100件のサンプルタスクを読み込む。**New task** に入力して **Add task** を
押すと、先頭に入力したタスクが追加されて件数が101件になる。一覧を縦にスクロールできる。

```bash
bash Scripts/swift_build.sh --product kswiftc
app=Tests/CompilerBackendTests/Fixtures/AndroidComposeView
bash "$app/build.sh"
adb install -r "$app/build/outputs/apk/debug/ComposeProbe-debug.apk"
adb shell am start -n org.swiftykotlin.composeprobe/.MainActivity
```

この例では `mutableStateOf(value)` の既定の変更ポリシー、`LazyColumn { ... }` の
既定のレイアウト設定、`items(count) { index -> ... }` の既定のキーを使う。
`OutlinedTextField` に文字列、変更コールバック、ラベルのラムダ、`singleLine` を渡す。
`ComposeView.setContent { ... }`、`Column { ... }`、`BasicText(String)`、および
`Button(onClick = { ... }) { ... }` は共通の composable 呼び出しとして使う。
