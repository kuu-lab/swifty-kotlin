# Android バックエンド（JVM → DEX/APK）

`kswiftc --emit dex|apk` は、JVM バックエンドが生成する classfile を Android
SDK のビルドツールで DEX / APK に変換する。APK にリソースを指定すると、
Kotlin コードから `R.layout.counter` や `R.id.count` を参照できる。

## 前提

- Android SDK がインストール済みであること（`platforms/android-*/android.jar`
  と `build-tools/<version>/` に `d8` を含む）。
- `--android-res` を使う場合は、JDK の `javac` が `JAVA_HOME/bin` または
  `PATH` にあること。
- SDK ルートの解決順: `--android-sdk` → `ANDROID_HOME` → `ANDROID_SDK_ROOT` →
  プラットフォーム既定のインストール先（macOS: `~/Library/Android/sdk`、
  Linux: `~/Android/Sdk`）。
- `--emit apk` の署名には keystore が必要。既定では `~/.android/debug.keystore`
  を使い、無ければ `keytool` で debug 鍵を生成する（Gradle の debug 署名と同じ）。

## カウンターアプリをビルドする

サンプルアプリは XML レイアウトを読み込み、ボタンを押すたびに画面のカウントを
更新する。[AndroidCounter のソース](../Tests/CompilerBackendTests/Fixtures/AndroidCounter)

リポジトリのルートから次のコマンドで署名付き APK を生成し、接続中の
Android 端末またはエミュレータにインストールできる。

```bash
app=Tests/CompilerBackendTests/Fixtures/AndroidCounter
.build/debug/kswiftc "$app/MainActivity.kt" --emit apk -o counter.apk \
    --manifest "$app/AndroidManifest.xml" --android-res "$app/res" --android-min-api 24
adb install -r counter.apk
adb shell am start -n org.swiftykotlin.androidprobe/.MainActivity
```

`--emit dex -o classes.dex.zip` は `classes*.dex` をまとめた ZIP を生成する。
アプリの `R` を参照するソースでは `--emit apk --android-res <dir>` を使う。

## オプション

| フラグ | 内容 |
| --- | --- |
| `--android-sdk <path>` | SDK ルート（既定: 環境変数・既定パスから自動検出） |
| `--android-build-tools <ver>` | build-tools バージョン（既定: 最新） |
| `--android-compile-sdk <api>` | `android.jar` を取る platform（既定: 最新） |
| `--android-min-api <n>` | `d8 --min-api` / `aapt2 --min-sdk-version` |
| `--manifest <path>` | `AndroidManifest.xml`（apk のみ） |
| `--android-res <dir>` | APK に取り込むリソースディレクトリ。manifest のパッケージに `R` を生成する |
| `--android-assets <dir>` | `aapt2 link -A` で同梱する assets |
| `--android-keystore <path>` | 署名 keystore（既定: debug.keystore） |
| `--android-key-alias <name>` | 鍵エイリアス（既定: `androiddebugkey`） |
| `--android-store-pass <pass>` | keystore パスワード（既定: `android`） |
| `--android-key-pass <pass>` | 鍵パスワード（既定: store パスワード） |

`--classpath` / `-jvm-target` も `dex` / `apk` で利用できる。classpath の
jar はそのまま `d8` の入力になり、ディレクトリは `--classpath` として渡る。

## 動作の内訳

1. **リソース**: APK に `--android-res` を指定すると、先に `aapt2 compile` と
   `aapt2 link --java` を実行する。生成した `R.java` を `javac` で
   classfile に変換し、Kotlin の型検査に渡す。[AAPT2 のドキュメント](https://developer.android.com/tools/aapt2)
2. **フロントエンド**: `dex` / `apk` は JVM パイプラインを共有する。
   `platforms/android-*/android.jar` を classpath に追加し、`android.*` や
   `java.*` のフレームワーク型を Sema から参照できるようにする。
   フレームワークのクラスは全件（10 万超）をシンボルテーブルに展開すると
   枯渇するため、**ユーザーコードから実際に参照されるクラスとその継承・
   シグネチャの推移閉包だけ**を Kotlin スタブ（`<kswiftk-jvm-import>/…`）
   として注入する lazy injection を行う。protected メンバーも取り込み、
   `Activity.onCreate(Bundle)` のような protected オーバーライドに対応する。
   JDK の mapped type（`java.util.List` → `kotlin.collections.List` 等）や
   `java.lang.Number`/`CharSequence`/`Appendable` は Kotlin 側の宣言に
   対応付け、シグネチャとスーパークラスで一貫した型になるよう調整する。
3. **コード生成**: 通常の JVM classfile/JAR 生成のあと、classpath 由来の
   スタブクラスを除外して `d8` に渡す（スタブはシグネチャ契約であり、
   実行時は android.jar の実装が使われる）。
4. **DEX**: `d8 --lib android.jar [--min-api n] --output out.zip classes.jar
   <classpath jars>` を実行し、`classes*.dex` を ZIP にまとめる。
5. **APK**: `aapt2 link` で作った APK に dex を `zip -0` で追加し、
   `zipalign` と `apksigner sign` を実行する。`--android-res` を指定した場合、
   自動生成した `R` と同じリソーステーブルを使う。
   途中生成物は一時ディレクトリに置き、全工程が成功してから出力先へ
   移動する。

## 既知の制限

- JVM バックエンド自体がサブセット実装のため、Android API のうち
  コンパイラが解釈できる Kotlin 機能の範囲に限られる。
- Kotlin から参照できる `R` のフィールドは整数定数に限られる。
- フレームワークスタブは宣言契約であり、実行時の振る舞いは android.jar
  側の実装に依存する。リソース・manifest・署名までをこのパイプラインが
  担い、実機での動作は別途検証が必要。
- `kotlinx` 系や Android 固有のリフレクションなど、JVM バックエンドが
  未対応の言語機能はそのまま制限になる。
