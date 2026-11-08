# Android バックエンド（JVM → DEX/APK）

`kswiftc --emit dex|apk` は、JVM バックエンドが生成する classfile を Android
SDK のビルドツールで DEX / APK に変換する。`--emit class|jar` の出力をそのまま
`d8` / `aapt2` / `zipalign` / `apksigner` に流す構成で、コンパイラ本体は
JDK・kotlinc・Android SDK のライブラリに依存しない（ツールの実行ファイルのみ
外部プロセスとして呼び出す）。

## 前提

- Android SDK がインストール済みであること（`platforms/android-*/android.jar`
  と `build-tools/<version>/` に `d8` を含む）。
- SDK ルートの解決順: `--android-sdk` → `ANDROID_HOME` → `ANDROID_SDK_ROOT` →
  プラットフォーム既定のインストール先（macOS: `~/Library/Android/sdk`、
  Linux: `~/Android/Sdk`）。
- `--emit apk` の署名には keystore が必要。既定では `~/.android/debug.keystore`
  を使い、無ければ `keytool` で debug 鍵を生成する（Gradle の debug 署名と同じ）。

## 使用例

```kotlin
// MainActivity.kt
import android.app.Activity
import android.os.Bundle

class MainActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
    }
}

fun main() { println("probe") }
```

```bash
# DEX（classes*.dex をまとめた ZIP）
.build/debug/kswiftc MainActivity.kt --emit dex -o classes.dex.zip

# APK（AndroidManifest.xml がカレントか app/src/main, src/main に必要）
.build/debug/kswiftc MainActivity.kt --emit apk -o app.apk \
    --android-min-api 24 --android-res app/src/main/res
```

## オプション

| フラグ | 内容 |
| --- | --- |
| `--android-sdk <path>` | SDK ルート（既定: 環境変数・既定パスから自動検出） |
| `--android-build-tools <ver>` | build-tools バージョン（既定: 最新） |
| `--android-compile-sdk <api>` | `android.jar` を取る platform（既定: 最新） |
| `--android-min-api <n>` | `d8 --min-api` / `aapt2 --min-sdk-version` |
| `--manifest <path>` | `AndroidManifest.xml`（apk のみ） |
| `--android-res <dir>` | `aapt2 compile` するリソースディレクトリ |
| `--android-assets <dir>` | `aapt2 link -A` で同梱する assets |
| `--android-keystore <path>` | 署名 keystore（既定: debug.keystore） |
| `--android-key-alias <name>` | 鍵エイリアス（既定: `androiddebugkey`） |
| `--android-store-pass <pass>` | keystore パスワード（既定: `android`） |
| `--android-key-pass <pass>` | 鍵パスワード（既定: store パスワード） |

`--classpath` / `-jvm-target` も `dex` / `apk` で利用できる。classpath の
jar はそのまま `d8` の入力になり、ディレクトリは `--classpath` として渡る。

## 動作の内訳

1. **フロントエンド**: `dex` / `apk` は JVM パイプラインを共有する。
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
2. **コード生成**: 通常の JVM classfile/JAR 生成のあと、classpath 由来の
   スタブクラスを除外して `d8` に渡す（スタブはシグネチャ契約であり、
   実行時は android.jar の実装が使われる）。
3. **DEX**: `d8 --lib android.jar [--min-api n] --output out.zip classes.jar
   <classpath jars>` を実行し、`classes*.dex` を ZIP にまとめる。
4. **APK**: `aapt2 link -o unsigned.apk -I android.jar --manifest …
   [--min-sdk-version n] [-A assets] [res.zip]` → `zip -0` で dex を
   ルートに追加 → `zipalign -f -p 4` → `apksigner sign`。
   途中生成物は一時ディレクトリに置き、全工程が成功してから出力先へ
   移動する。

## 既知の制限

- JVM バックエンド自体がサブセット実装のため、Android API のうち
  コンパイラが解釈できる Kotlin 機能の範囲に限られる。
- フレームワークスタブは宣言契約であり、実行時の振る舞いは android.jar
  側の実装に依存する。リソース・manifest・署名までをこのパイプラインが
  担い、実機での動作は別途検証が必要。
- `kotlinx` 系や Android 固有のリフレクションなど、JVM バックエンドが
  未対応の言語機能はそのまま制限になる。
