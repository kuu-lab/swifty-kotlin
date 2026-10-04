# kotlinx.io バンドル対応の現状

`docs/ktor-build-status.md`（未マージ、branch `claude/ktor-build-support-5ab969`）が最大のブロッカーとして
挙げた「`kotlinx.io` がバンドル stdlib に一切実装されていない」に対応した記録。

## 実装したもの

`Sources/CompilerCore/Stdlib/kotlinx/io/` に、kotlinx-io 0.9.1（`core/common/src`）を参考にした
簡略版を Kotlin ソースとして追加した。

- `RawSource` / `RawSink`（`RawSink` は upstream で `expect interface` だが、このコンパイラは単一
  ターゲットなので plain interface にした）
- `Source` / `Sink`（upstream と同じ sealed interface。
  KUU-655 の修正により、ByteArray 入出力のデフォルト引数も復元した）
- `Buffer`（`Source`/`Sink` を実装する具象クラス）
- `IOException` / `EOFException`（upstream は `expect`/`actual` だが、single-target なので plain
  class にした）
- `RealSource` / `RealSink`（`RawSource.buffered()` / `RawSink.buffered()` の内部実装）
- `PeekSource`（`Source.peek()` の内部実装）
- `Core.kt`（`buffered()` 拡張関数2つ、`discardingSink()`、`SystemLineSeparator`）
- `Segment.kt` / `SegmentPool.kt`（upstream `core/common/src` を移植。`expect object SegmentPool`
  は単一ターゲット前提で upstream の native actual と同じ no-op プール（`MAX_SIZE = 0`、
  `take()` は常に新規割当、`recycle()` は no-op）に置き換え、`@JvmField`/`@JvmSynthetic` は除去。
  `SegmentCopyTracker`/`AlwaysSharedCopyTracker` と `indexOf`/`indexOfBytesInbound`/
  `indexOfBytesOutbound`/`isEmpty` の `Segment` 拡張も同ファイルに同梱。`Segment` 自体は
  upstream 同様 `public` だが全メンバが `internal` なので public surface は変わらない）
- `Sources.kt`（0.9.1 の Source 拡張一式：decimal/hex 読み込み、LE/unsigned/浮動小数点、
  ByteArray 読み込み、byte 検索、`startsWith`。`ByteStrings.kt` の Source/Buffer 検索・
  ByteString 取得も同梱）

`readUnsignedByte` 等ではなく upstream の `readUByte` / `readUShort` / `readUInt` / `readULong`
を公開する。0.9.1 の `Sources.kt` には `select(OPTIONAL_*)` / `segmentedBytes` は存在しない。

### Buffer のセグメントリング（KSP-1548）

`Buffer` は 8192 バイトの `BufferSegment` を双方向リングとして保持する。
全セグメントの転送は所有権移動、`copy`/`copyTo` は読み取り範囲と配列の共有で実装し、
共有済み領域を上書きしない。`size` は独立した `Long` カウンタで管理する。
upstream の `Segment` / `SegmentPool` は追加済みだが、現行 `Buffer` は内部の `BufferSegment`
を使用しており未移行。`unsafe.UnsafeBufferOperations` は引き続き未対応。

`readAtMostTo(ByteArray)` は upstream と同じく先頭セグメントだけを読み、
`skip` が EOF に達した場合は残存バイトを消費してから例外を投げる。
`PeekSource` は先頭セグメントの identity と位置で無効化を検出し、
`RealSink.hintEmit` はサイズの倍数ではなく完全なセグメントを送出する。

**新規 Runtime ABI（`@_cdecl kk_*`）は一切追加していない。** `ByteArray` の読み書きは
既存の bundled stdlib プリミティブ（配列インデクシング、`toInt()`/`toLong()`/`toByte()`変換）だけで
書けたため、`docs/spec.md` の Runtime ABI spec 登録（Doc J16 節）は今回は不要だった。

## JVM 相互運用（KSP-1553）

`kotlinx.io` ↔ `java.io` の相互運用拡張を upstream `core/jvm` sourceset のファイル名規約に
合わせて追加した（KUU-889）。

- `JvmCore.kt`: `InputStream.asSource()` / `OutputStream.asSink()`（upstream の
  `InputStreamSource`/`OutputStreamSink` 相当の private `RawSource`/`RawSink` 実装。
  合成 `java.io` stream stub は単バイト `read()`/`write(Int)` と `List<Int>` バルク入出力しか
  持たず `ByteArray`（= `RuntimeArrayBox`）と型が合わないため、upstream の
  `UnsafeBufferOperations` セグメントコピーの代わりに per-byte ループにしている。
  `OutputStreamSink.write` は upstream と同じく `checkOffsetAndCount(source.size, 0, byteCount)`
  で事前にバウンドチェックする）
- `SourcesJvm.kt`: `Source.asInputStream()`
- `SinksJvm.kt`: `Sink.asOutputStream()` + `@KsSymbolName("__kk_kotlin_sink_output_stream")`
  external 宣言（upstream の `anonymous object : OutputStream()` を、write/flush/close の
  3 コールバックをランタイムに渡す形に置き換え）

### upstream との差分（意図的）

- **`asInputStream()` は eager drain。** upstream は `InputStream` サブクラスが source を遅延
  pull するが、このコンパイラでは `java.io.InputStream` を Kotlin ソースからサブクラス化できず、
  `RuntimeInputStreamBox` の既存メソッドは全て非 throws で Kotlin 例外を伝搬する経路がない。
  `transferTo(Buffer)` → `ByteArray.inputStream()` で全量を取り込む。結果として「遅延読み取り
  しない」「`close()` が source に伝播しない」「読み取り失敗が read() ではなく adapt 時に
  出る」点で upstream と異なる。
- **`asOutputStream()` の closed 意味論は upstream と同じく sink 側に委譲**（`is RealSink` →
  `sink.closed`、`is Buffer` / その他 → `false`）。`RealSink.closed` は upstream の
  `@JvmField var closed` に合わせて `private` → `internal` に変更。close 後の `write()` は
  `java.io.IOException("Underlying sink is closed.")` を投げる。upstream の
  `kotlinx.io.IOException` は `java.io.IOException` への typealias なので java.io 側を投げるのが
  意味論として正確（かつ、このコンパイラでは catch 節の `IOException` が `java.io.IOException`
  に解決されるため、catch 可能なのはこちら。後述の KUU-950 参照）。
- **`asOutputStream()` の write コールバックは `sink.write(bytes, 0, bytes.size)` を呼ぶ。**
  upstream は `writeToInternalBuffer`（`@DelicateIoApi`）で RealSink の内部バッファへ直接
  書き込むが、closed チェックは callback 側の `isClosed()` で先行して行うため観測差はない。

### 新規 Runtime ABI: `__kk_kotlin_sink_output_stream`

`java.io.OutputStream` を Kotlin ソースから生成する経路がランタイムに一切なかった
（`HeaderHelpers+SyntheticJavaIOStreamStubs.swift` に "unconstructible from Kotlin source" と
明記）ため、`__kk_cdecl_count` +1 で `(writeFnPtr, writeClosureRaw, flushFnPtr, flushClosureRaw,
closeFnPtr, closeClosureRaw) -> streamRaw` を追加した。呼び出し側は
`CallLowerer+ClosureAdapters.swift` の `appendClosureArgumentsIfNeeded` で
`makeCollectionHOFExpandedArguments`（`(ByteArray) -> Unit`）と
`makeClosureThunkExpandedArguments`（`() -> Unit` × 2）を連結する既存 ABI 規約そのまま。

ランタイム側は既存プロトコル `RuntimeOutputStreamSink` の実装 `RuntimeKotlinOutputStreamSink`
を追加し、3 つの `(fnPtr, closureRaw)` ペアを `runtimeInvokeCollectionLambda1` /
`runtimeInvokeClosureThunk` で呼び返す。コールバック内で投げられた Kotlin throwable は
`RuntimeKotlinThrownError` で包み直し、`__kk_output_stream_write_byte` /
`__kk_output_stream_write_bytes` / `__kk_output_stream_flush` の `outThrown` チャネルから
呼び出し元へ返す（`close()` は outThrown を持たないため close コールバックの例外は握り潰す。
`RuntimeFileHandleOutputStreamSink.close` の `try?` と同じ扱い）。

### diff_cases（kotlinc 実機比較）

`Scripts/diff_cases/kotlinx_io_jvm_interop_{as_source,as_sink,as_input_stream,as_output_stream}.kt`
を追加し、`kotlinc` + `kotlinx-io-core-jvm` 0.9.1 と出力完全一致を確認。`as_output_stream`
ケースは upstream の closed 意味論（Buffer-backed は close 後も書き込みが流れる、
RealSink-backed は `IOException("Underlying sink is closed.")`）の両枝を検証する。

## 未対応（次PR以降）

- `kotlinx.io.unsafe.UnsafeBufferOperations`（低レベルなセグメント直接
  操作。Ktor の `ktor-io` が一部使用しているため、`ktor_io` モジュールの残存エラーの一因。
  基盤の `Segment`/`SegmentPool` は追加済み）
- `JvmCore.kt` の残り: `SystemLineSeparator` actual は `Core.kt` 側で実装済み。`SourcesJvm.kt` /
  `SinksJvm.kt` の残り（`readString`, `writeString`, `readAtMostTo`/`write` ByteBuffer,
  `asByteChannel`）は ByteBuffer/NIO 依存のため未対応
- `Sink.asOutputStream()` の `close()` で `sink.close()` が投げる例外はランタイム側で
  握り潰される（upstream の OutputStream.close() は例外を伝播するが、
  `__kk_output_stream_close` に outThrown チャネルがない）
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
その後 master 側で下記バグ3（同名・受信型違いの隣接拡張関数の解決）が解消されたため、ユーザ定義
`RawSource`/`RawSink` に対する `.buffered()` の read/write（close 伝播・flush タイミング含む）も
同ケースに復活させている（kotlinc + kotlinx-io-core-jvm 0.9.1 と出力一致）。

## 見つけたコンパイラバグ（kotlinx.io 実装とは別件、このセッションでは修正せず）

**KUU-950（起票済み、KSP-1553 作業中に発見）**: catch 節の例外型解決が同名クラスで
`java.io.IOException` を優先し、bundled `kotlinx.io.IOException` が catch できない
（qualified name / alias も catch 節では `KSWIFTK-SEMA-0085` で受理されない）。
KSP-1553 では adapter が `java.io.IOException` を投げることで回避済み。

以下 3 件は前セッション時点で Linear への起票手段が無かったため（`docs/ktor-build-status.md`
と同じ制約）ここに記録する。team `Kuu` / project「バグバックログ (BUG)」/ label `Bug` への
起票が必要。

1. **`operator fun get(position: Long)` のブラケット記法 (`x[i]`) が壊れている。** `get(Long): Byte`
   を bracket 経由で呼ぶと、`i=0,1` は `0` を返し、`i=2` では `Byte` ではなく内部の `ByteArray`
   フィールドそのものを返す（`println` すると `[1, 2, 3, ...]` のような配列表示になる）。
   `.get(0L)` のように明示的にメソッド呼び出しすれば正しい値が返る。`operator fun get(position: Int)`
   は bracket 記法でも正しく動く。`Buffer.get(position: Long): Byte`（upstream の実 API 形状）は
   このバグの影響を受けるため、diff_cases では `buf.get(0L)` の明示呼び出しに置き換えて検証した。
2. **旧制限（KUU-655 で修正済み）：`open`/インターフェースメンバのデフォルト引数。**
   抽象（インターフェース）メンバにデフォルト値を付けて省略呼び出しすると、`_fn$default` 相当の
   ブリッジが生成されず `Undefined symbols` でリンクエラーになる。`open class` の場合は
   ブリッジ自体は生成されるが、**デフォルト値で埋めた引数を使って呼び出す際に override 先の
   本体ではなく宣言元（base）の本体を呼んでしまう**（黒魔術的な正しさの静かな崩壊。
   `open fun f(x: Int, y: Int = 100)` を override した派生クラスを基底型経由で `d.f(5)` と呼ぶと、
   デフォルト値 `100` は正しく補われるが、実行されるのは base の本体）。このため `Source`/`Sink`
   のインターフェースメンバのデフォルト値を当初は除外した。KSP-1548 ではデフォルト値を復元し、
   Source/Sink 型経由および Buffer 型経由の省略呼び出しを回帰ケースで検証する。
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
   **追記（KUU-885 作業時）:** `RawSource.buffered()`/`RawSink.buffered()` のパターンは現行 master
   （`dec047057` 時点）で解消済みを確認（ユーザ定義 `RawSource`/`RawSink` に対する `.buffered()`
   呼び出しが解決し、出力も kotlinc と一致）。`Source.preview()`/`Sink.preview()` 側の Ktor 再現
   パターンは未再検証。

## 参考：`equal-constraint-lub-glb-pollution-bug` メモリの追記について

同メモリは「2026-09-20 現在、バンドル stdlib の自己コンパイルが master で壊れている」と記録していたが、
このPR作業でこの worktree の HEAD（`6a18331a0d`）で `--stdlib-only` / `--stdlib-from-source` の両方が
クリーンに（exit 0）成功することを確認した。別セッションの環境固有の問題だったか、その後 master 側で
解消された可能性がある。メモリは本PRの一環で更新した。
