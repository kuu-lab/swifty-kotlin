# Kotlin Android Compose counter

`MainActivity.kt` を kswiftc でコンパイルする。`ComposeView.setContent` に Kotlin の
composable ラムダを渡し、Compose Foundation の `Column` に `BasicText` と
Material 3 の `Button` を配置する。ボタンを押すと `mutableIntStateOf` の値が変わり、
テキストが再コンポジションされる。

Gradle は AndroidX Compose 1.7.8 と Compose Material 3 1.3.2 を取得し、APK の Kotlin 標準ライブラリは
`kswiftc --stdlib-only` でこのリポジトリから生成する。

Android SDK 36.1、Build Tools 36.1.0、Gradle 9.8、JDK、Python 3 を用意し、リポジトリのルートで実行する。
起動後に **Increment** を押すと `Compose count: 0` が `Compose count: 1` に変わる。

```bash
bash Scripts/swift_build.sh --product kswiftc
app=Tests/CompilerBackendTests/Fixtures/AndroidComposeView
bash "$app/build.sh"
adb install -r "$app/build/outputs/apk/debug/ComposeProbe-debug.apk"
adb shell am start -n org.swiftykotlin.composeprobe/.MainActivity
```

外部 API の対応範囲は `ComposeView.setContent { ... }`、`MutableIntState.intValue`、
`mutableIntStateOf(Int)`、既定の引数を使う `BasicText(String)`、`Column { ... }`、
`Button(onClick = { ... }) { ... }`。これらの composable コンテンツにはラムダリテラルを渡す。
