# kotlinx.io バンドル対応の現状

`docs/ktor-build-status.md`（未マージ、branch `claude/ktor-build-support-5ab969`）が最大のブロッカーとして
挙げた「`kotlinx.io` がバンドル stdlib に一切実装されていない」に対応した記録。

## 実装したもの

`Sources/CompilerCore/Stdlib/kotlinx/io/` に、kotlinx-io 0.9.1（`core/common/src`）を参考にした
簡略版を Kotlin ソースとして追加した。

- `RawSource` / `RawSink`（`RawSink` は upstream で `expect interface` だが、このコンパイラは単一
  ターゲットなので plain interface にした）
- `Source` / `Sink`（upstream の `sealed` は外した。このインターフェースを網羅的に `when` する
  コードは無く、後述するインターフェースメンバのデフォルト引数バグを避けるため、デフォルト値を
  持つメンバ宣言も避けた）
- `Buffer`（`Source`/`Sink` を実装する具象クラス）
- `IOException` / `EOFException`（upstream は `expect`/`actual` だが、single-target なので plain
  class にした）
- `RealSource` / `RealSink`（`RawSource.buffered()` / `RawSink.buffered()` の内部実装）
- `PeekSource`（`Source.peek()` の内部実装）
- `Core.kt`（`buffered()` 拡張関数2つ、`discardingSink()`、`SystemLineSeparator`）

### 内部実装の簡略化：セグメント連結リストではなく単一 ByteArray

upstream の `Buffer` は、コピーを避けるためプールされた `Segment`（固定長 `ByteArray` チャンク）の
双方向連結リストとしてバイト列を持つ。今回のポートでは `Segment` / `SegmentPool` /
`unsafe.UnsafeBufferOperations` は実装せず、`Buffer` を単一の可変長 `ByteArray` ＋ `start`/`end`
カーソルで実装した。外部から観測できる挙動（読み書きした値・例外・`size`）は upstream と一致する
（後述の diff_cases で確認済み）。バッファ間のセグメント所有権移動によるゼロコピーのような内部最適化は
無くなるが、正当性には影響しない。

**この簡略化により、新規 Runtime ABI（`@_cdecl kk_*`）は一切追加していない。** `ByteArray` の読み書きは
既存の bundled stdlib プリミティブ（配列インデクシング、`toInt()`/`toLong()`/`toByte()`変換）だけで
書けたため、`docs/spec.md` の Runtime ABI spec 登録（Doc J16 節）は今回は不要だった。

## 未対応（次PR以降）

- `Segment` / `SegmentPool` / `kotlinx.io.unsafe.UnsafeBufferOperations`（低レベルなセグメント直接
  操作。Ktor の `ktor-io` が一部使用しているため、`ktor_io` モジュールの残存エラーの一因）
- `Sources.kt` / `Sinks.kt` の拡張関数群（`readByteArray`, `readString`, `writeString`,
  `readUByte`/`writeUShort`等の unsigned 変換, `readFloat`/`writeDouble`, `readDecimalLong`,
  `readHexadecimalUnsignedLong`, `writeToInternalBuffer` 等）
- `Buffers.kt` の `Buffer.snapshot()`（`ByteString` が必要）
- `kotlinx.io.bytestring`（`ByteString`, `ByteStringBuilder`, `Base64`, `Hex`,
  `UnsafeByteStringOperations`）— ユーザ依頼の「ByteString」PR に相当
- `kotlinx.io.files`（`FileSystem`, `Path`）

## 計測：`Scripts/ktor_build.sh`

`Scripts/ktor_build.sh` は現在の master には無い（`docs/ktor-build-status.md` と同じ未マージ branch
のみ）。このPRでは同スクリプトを `7d3857f15d`（同branchの直近コミット）からコピーし、
`KSWIFTC_FLAGS` 環境変数（既存の `KSWIFTC` 変数と同様の追加フラグ渡し）を1点追加した。これは
`~/Library/Caches/kswiftk/stdlib/` の共有キャッシュ（他セッションと共有、計測中に stale/mid-write に
なりうる）を経由せず `--stdlib-library <path>` で明示的に stdlib を指定するための変更。

このPRの変更を適用する前後で `kotlinx_io` / `ktor_io` / `ktor_utils` / `ktor_http` の4モジュールを
比較した（`kswiftc --stdlib-only` で作った変更前後それぞれの `.kklib` を `KSWIFTC_FLAGS` で指定）。

| module | before errors | after errors | before "Buffer/Source/Sink 系 Unresolved" | after 同 |
|---|---|---|---|---|
| kotlinx_io | 205 | 326 | 0※ | 0※ |
| ktor_io | 412 | 245 | 78 | 4 |
| ktor_utils | 2 | 2 | 0 | 0 |
| ktor_http | 1 | 1 | 0 | 0 |

※ `kotlinx_io` モジュールは upstream の実ソース（`Buffer.kt` 等）をユーザコードとしてそのまま
コンパイルするため、バンドルした同名宣言と衝突し「重複宣言」警告が新たに出る。これは意図した
挙動（`Duplicate declaration is advisory`。KSWIFTK-SEMA-0001 はビルドを止めない）。この
モジュール自体のエラー総数が減らない/増えるのは、`Segment` 等の未実装 API に依存するファイルが
（Buffer/Source/Sink が解決するようになった分）より先まで進んで別の未実装箇所にぶつかるようになった
ため。**「Unresolved function/type 'Buffer'/'Source'/'Sink'」を優先して減らす**という当初の目標に
対する実質的な計測値は `ktor_io`（Ktor 側が kotlinx.io を実際に消費する側）で、
**78 件 → 4 件**（-95%）。残る4件は既知のコンパイラバグ（後述）1件に起因（`ByteReadPacket.kt` /
`Copy.kt` / `Strings.kt` で `Source.preview()` の直後に `Sink.preview()` を宣言している箇所）。

`ktor_utils`/`ktor_http` の残存1〜2件は `KSWIFTK-PARSE-0004`/`0006`/`0002`（パーサ側、
`docs/ktor-build-status.md` の未マージ branch が対応済みの既知バグ群）であり、kotlinx.io とは無関係。

## diff_cases（kotlinc 実機比較）

`Scripts/diff_cases/kotlinx_io_buffer_basic.kt` / `kotlinx_io_buffered_source_sink.kt` /
`kotlinx_io_eof_exception.kt` を追加し、`kotlinc` + 実際の `kotlinx-io-core-jvm` 0.9.1（Maven Central、
SHA-256 で pin）と出力が完全一致することを確認した。`Scripts/diff_kotlinc.sh` に
`requires_kotlinx_io`/`ensure_kotlinx_io_jar`（既存の `kotlinx.coroutines` 用ダウンロード機構と同型）を
追加し、`bash Scripts/diff_kotlinc.sh <file>` で自動的に依存 jar を取得・検証できるようにした。

`kotlinx_io_buffered_source_sink.kt` は当初、ユーザ定義クラスが `RawSource`/`RawSink` を実装して
`.buffered()` を呼ぶケースを含めていたが、下記のコンパイラバグで解決できないため、`Buffer.peek()`
（`PeekSource`/`RealSource` を内部的に経由）と `discardingSink()` のみを使う形に絞った。

## 見つけたコンパイラバグ（kotlinx.io 実装とは別件、このセッションでは修正せず）

Linear への起票手段がこのセッションに無かったため（`docs/ktor-build-status.md` と同じ制約）、
ここに記録する。team `Kuu` / project「バグバックログ (BUG)」/ label `Bug` への起票が必要。

1. **`operator fun get(position: Long)` のブラケット記法 (`x[i]`) が壊れている。** `get(Long): Byte`
   を bracket 経由で呼ぶと、`i=0,1` は `0` を返し、`i=2` では `Byte` ではなく内部の `ByteArray`
   フィールドそのものを返す（`println` すると `[1, 2, 3, ...]` のような配列表示になる）。
   `.get(0L)` のように明示的にメソッド呼び出しすれば正しい値が返る。`operator fun get(position: Int)`
   は bracket 記法でも正しく動く。`Buffer.get(position: Long): Byte`（upstream の実 API 形状）は
   このバグの影響を受けるため、diff_cases では `buf.get(0L)` の明示呼び出しに置き換えて検証した。
2. **`open`/インターフェースメンバのデフォルト引数と virtual dispatch が噛み合っていない。**
   抽象（インターフェース）メンバにデフォルト値を付けて省略呼び出しすると、`_fn$default` 相当の
   ブリッジが生成されず `Undefined symbols` でリンクエラーになる。`open class` の場合は
   ブリッジ自体は生成されるが、**デフォルト値で埋めた引数を使って呼び出す際に override 先の
   本体ではなく宣言元（base）の本体を呼んでしまう**（黒魔術的な正しさの静かな崩壊。
   `open fun f(x: Int, y: Int = 100)` を override した派生クラスを基底型経由で `d.f(5)` と呼ぶと、
   デフォルト値 `100` は正しく補われるが、実行されるのは base の本体）。このため `Source`/`Sink`
   のインターフェースメンバには一切デフォルト値を付けず、代わりに拡張関数側にデフォルト値付きの
   簡略形を用意する設計にした。
3. **同名で受信型だけ異なる2つの拡張関数を隣接して宣言すると、片方（またはそのユーザ実装先の
   サブクラス）から解決できなくなることがある。** `public fun RawSource.buffered(): Source = ...`
   と `public fun RawSink.buffered(): Sink = ...` を同じファイルに並べて宣言した場合、
   ユーザコードで独自の `RawSource` 実装クラスに対して `.buffered()` を呼ぶと
   `KSWIFTK-SEMA-0024: Unresolved member function 'buffered'` になる（バンドル
   stdlib 内で同じ手続き経由（`Buffer.peek()` → `PeekSource(this).buffered()`）で呼ぶ分には
   問題なく解決する）。Ktor 本体の `ByteReadPacket.kt` にある `Source.preview()`/`Sink.preview()`
   の隣接宣言でも同じ症状（`ktor_io` の残存エラー参照）で再現しており、kotlinx.io 固有の問題ではない。
   切り分け中に確認した副次的な事実（別バグの可能性）：新規追加インターフェースを `val x: T = Ctor()`
   のような expected-type 文脈でコンストラクタ呼び出しの対象にすると `No viable overload found`
   になるケースがあり、既存の `AutoCloseable` では発生しない（新規追加インターフェース固有の
   何らかの登録漏れの可能性）。

## 参考：`equal-constraint-lub-glb-pollution-bug` メモリの追記について

同メモリは「2026-09-20 現在、バンドル stdlib の自己コンパイルが master で壊れている」と記録していたが、
このPR作業でこの worktree の HEAD（`6a18331a0d`）で `--stdlib-only` / `--stdlib-from-source` の両方が
クリーンに（exit 0）成功することを確認した。別セッションの環境固有の問題だったか、その後 master 側で
解消された可能性がある。メモリは本PRの一環で更新した。
