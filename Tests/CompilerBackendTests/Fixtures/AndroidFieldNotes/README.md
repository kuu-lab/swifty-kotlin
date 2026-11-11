# Field Notes

一覧と編集の 2 画面を持つ Android アプリ。メモの追加・編集・削除を端末の
SQLite に保存し、一覧からタイトルと本文を検索できる。

ビルドには Android のリソース生成と Java のジェネリックな戻り値に対応した
kswiftc が必要。[PR #12974](https://github.com/kuu-lab/swifty-kotlin/pull/12974)

Android SDK 36.1、Build Tools 36.1.0、JDK と、Kotlin 2.4.20 の配布物に
含まれる `kotlin-stdlib.jar` を使う。`stdlib` にパスを設定し、リポジトリの
ルートで実行する。

```bash
app=Tests/CompilerBackendTests/Fixtures/AndroidFieldNotes
stdlib=/path/to/kotlin-stdlib.jar
.build/debug/kswiftc "$app/NotesActivity.kt" "$app/EditActivity.kt" "$app/NoteStore.kt" \
    --emit apk -o field-notes.apk --manifest "$app/AndroidManifest.xml" \
    --android-res "$app/res" --android-min-api 24 --classpath "$stdlib"
adb install -r field-notes.apk
adb shell am start -n org.swiftykotlin.fieldnotes/.NotesActivity
```
