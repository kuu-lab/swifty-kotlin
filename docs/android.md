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

## AndroidX などの依存を使うアプリ（Gradle なし）

`--android-dependency group:artifact:version` を指定すると、kswiftc が依存を推移的に
解決して APK に取り込む。Gradle の `implementation` 依存と同じ扱いになる。
[Compose の例の build.sh](../Tests/CompilerBackendTests/Fixtures/AndroidComposeView/build.sh) は
7 つの依存を指定し、Gradle の `debugRuntimeClasspath` と同じ 52 モジュールに解決される。

```bash
app=Tests/CompilerBackendTests/Fixtures/AndroidComposeView
bash "$app/build.sh"            # kswiftc ... --emit apk --android-dependency ... -include-runtime
bash "$app/build.sh" --offline  # 2 回目以降はキャッシュだけで解決できる
```

- **解決**: Gradle Module Metadata（`.module`）を優先し、Android/JVM の runtime
  variant を選ぶ。Kotlin Multiplatform のルート（`androidx.compose.ui:ui`）は
  `available-at` で Android 版（`ui-android`）に読み替える。メタデータが無い
  artifact は POM（`compile`/`runtime` スコープ、親 POM のプロパティと
  `dependencyManagement`）を読む。バージョン競合は Gradle と同じく最も新しい
  ものを選び、`dependencyConstraints` もグラフ内のモジュールに適用する。
- **リポジトリ**: 既定は Google Maven → Maven Central。`--maven-repository <url>`
  で置き換えられる（`file://` 可）。ダウンロードは `.sha1` で検証し、
  `~/.kswiftk/maven`（`--maven-cache` / `KSWIFTK_MAVEN_CACHE`）にキャッシュする。
  `--offline` はキャッシュだけで解決する。
- **Kotlin 標準ライブラリ**: `org.jetbrains.kotlin:kotlin-stdlib*` と `kotlin-reflect`
  は解決から除外し、`-include-runtime`（または `--stdlib-only` で作った jar を
  `--classpath` に渡す）でこのリポジトリの標準ライブラリを同梱する。
- **AAR**: `classes.jar` と `libs/*.jar` を classpath（Sema は lazy injection）と
  d8 の入力にする。`res/` は `aapt2 compile` してオーバーレイとしてリンクし、
  ライブラリのパッケージごとに `R` を生成して dex に含める（Kotlin からは
  アプリの `R` だけが見える）。`assets/` と `jni/<abi>/*.so` も同梱する。
  ローカルの `.aar` / `.jar` は `--android-library <path>` で渡せる。
- **manifest のマージ**: ライブラリの manifest をアプリの manifest にマージする。
  `${applicationId}` の置換、相対クラス名の展開、タグと `android:name` が同じ
  要素の属性・子要素のマージ（`androidx.startup` の `InitializationProvider` に
  各ライブラリの `<meta-data>` が集まる）、アプリ側の `tools:node="remove"` に対応する。
  manifest に `package` が無い場合は `--android-namespace` を指定する。
- **Java リソース**: jar の非 class エントリ（`META-INF/services/*` など）を APK に
  入れる。ライセンス・署名・Maven メタデータ・`*.kotlin_module` は AGP の既定と
  同じく除外する。
- **Java ソース**: 入力に `.java` を渡すと、Kotlin より先に `javac` でコンパイルし、
  Kotlin から呼べるようにする。Java から Kotlin ソースは参照できない。

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
| `--android-dependency <g:a:v>` | Maven 依存（推移的に解決、複数指定可） |
| `--android-library <path>` | ローカルの `.aar` / `.jar`（複数指定可） |
| `--maven-repository <url>` | 依存の解決先（既定: Google Maven、Maven Central。複数指定可） |
| `--maven-cache <dir>` | ダウンロードキャッシュ（既定: `~/.kswiftk/maven`） |
| `--offline` | キャッシュだけで依存を解決する |
| `--android-namespace <package>` | manifest に `package` が無いときのアプリの `R` パッケージ（apk のみ） |
| `--android-application-id <id>` | アプリケーション ID（既定: namespace。apk のみ） |
| `--android-target-sdk <api>` | `targetSdkVersion`（apk のみ） |
| `--android-version-code <n>` / `--android-version-name <name>` | バージョン（apk のみ） |
| `--android-debuggable` | `android:debuggable="true"` を付ける（apk のみ） |
| `-include-runtime` | Kotlin 標準ライブラリを dex に同梱する（jar / dex / apk） |

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
- 依存解決は依存ごとの `excludes` と、単一バージョン固定（`[1.2]`）以外の
  バージョン範囲を扱わない。manifest マージは AGP のマージルールのうち
  上記の範囲だけを実装している（`tools:replace` などは無視して除去する）。
- `@Composable` な関数型パラメータを取る Kotlin のクラスメンバ（例: `LazyListScope.item { ... }`）は、
  classpath スタブでラムダの `@Composable` が失われるため、composable 呼び出しを含むラムダを渡すと
  KSWIFTK-SEMA-0493 になる。`LazyListScope.items(count) { ... }` は手書きの Compose 契約を
  メンバより優先して扱う。
