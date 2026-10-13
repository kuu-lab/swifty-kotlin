# KUU-1733 / IO-B04 UTF-8、行、code point の検証境界

対象は kotlinx-io 0.9.1、upstream commit
`362bdc35e159bad6da1e08101c8321792d762281`。直接前提は KUU-1727。
この変更案だけで元 upstream 全件の合格や paired coverage を主張しない。

## 修正する具体的な差分

既存の `Sink.writeString(CharSequence)` はサイズ計算と ByteArray エンコードで
getter を二度読む。固定 upstream は buffer の segment へ直接書き、読取り順、
例外までに完了した書込み、hintEmit のタイミングも契約の一部になる。
固定 JVM 参照で `ObservedChars("AB")` の getter 順は `01`、2 文字目で
throw する `ThrowingChars` は先行する `é` の `c3a9` を buffer に残した。
二段階の preflight はそれぞれ `0101` と未書込みを生むソース経路である。
これは現候補バイナリを実行して得た結果ではない。

閉じた実 buffered Sink に `writeString("X")` を呼ぶと、公式 0.9.1 は内部
buffer に `58` を書いた後に `hintEmit` の `IllegalStateException` を投げる。
既存の ByteArray 経由では `Sink.write` の closed check が先行する。
修正は公式の `writeToInternalBuffer` と private streaming helpers を使う。
同じ direct encoding に code point 書込みを揃え、孤立 surrogate は `?` として
書く。既存 String 変換経路の候補挙動は未測定である。

途中 EOF の code point 読取りは入力を消費しない。Buffer では例えば
`e2 82` に対して `size < 3: 2 (to read code point prefixed 0xe2)`、一般 Source
では `Source doesn't contain required number of bytes (3).` となる。
Buffer へも一律 `require(n)` を適用していた既存処理を、公式の Buffer 専用
helper と一般 Source の request/require 経路へ分ける。

`readString`、`readLine`、`readLineStrict` と internal decoder のロジックは
この案では変更しない。malformed UTF-8 の置換／消費範囲は静的比較し、同じ
回帰 oracle に含める。公式公開 9 overload／internal `String.utf8Size` の
visibility、型、default と直接 OptIn annotations を維持する。
OptIn は API の利用者へ新たな opt-in を要求する marker annotation ではない。
Runtime ABI、compiler 名称 whitelist、synthetic API は追加しない。

## 実測済みの参照

新規 `kotlinx_io_utf8_contract_boundaries.kt` は元テストの置換ではない。
Java 21／Kotlin 2.3.10、固定 0.9.1 core／bytestring JVM jars で一度だけ
compile/run し、双方 exit 0、stdout は 40 行。
source SHA256 は `e01e3214934e6a7b664ae77790c93daba00d1aba2e5e97ea99ce67e79d7b449f`、
stdout／`.expected` は
`ef3a687f1d31d5284351bdae1335711e575a81e8d374ccf7e12fe2f1225c2185`。
compile 60 秒、run 10 秒、whole 90 秒、heap 256 MiB を上限とし、入力前後
hash と subprocess の wait/reap、raw stdout/stderr を別 receipt に保存した。

40 行は invalid/truncated/overlong/surrogate/out-of-range UTF-8、UTF-16 孤立
surrogate／範囲で切れた pair、CharSequence の読取りと途中例外、code point
上下限／例外型と message／未消費 bytes、閉じた Sink、LF／CRLF／bare CR／
EOF、strict limit と multibyte の byte 境界、8191-byte prefix と segment 跨ぎを覆う。
`readLineStrict(0)` は先頭 LF／CRLF を受理する実値を固定した。upstream KDoc
の「常に EOF」という文から期待値を作っていない。

## 元テスト台帳

固定 `Utf8Test.kt` の 39 parameterless original IDs を、function inventory と
Native execution catalog の両方に照合した。abstract source の 124 methods
は元の 6 factory classes へ展開して 744 IDs、sink の 47 methods は 2 classes
へ展開して 94 IDs。合計 877 IDs の driver を scratch に保存した。
各呼出しは新しい元 concrete constructor、元 assertions／parameters／factory
bodies をそのまま使う。Linux 35-file closure は既存 59-byte friend-access
preamble 以外 byte 同一。`SystemLineSeparatorTest` の別 1 ID は OS の改行定数
を調べるもので、この UTF-8 source/sink driver の選択外として明記した。

全 877 IDs の candidate status は NOT_RUN、paired status は UNMAPPED。
元 function 台帳は factory 展開件数を意味しない。API token を含む method の
487 行という静的 locator も assertion mapping／実測 coverage 件数ではない。
既存のローカル fixture が存在することを original suite の合格根拠にしない。

## 実装後の有限ゲート

1. 新しい compiler と resources を対応させて fresh build し、Core の
   `KotlinxIOUtf8ContractSurfaceTests` を実行する。2 methods／10 cases は実
   source／実 stdlib artifact の公開 overload、default、nullable return、alias、
   個々の private／Okio homonym 呼出し拒否を確認する。古い artifact や source
   fallback を使わない。
2. `KotlinxIOUtf8ContractsExecutionTests` の 2 methods／8 cases を実行する。
   source／library、O0／O2 の 40 行 stdout の完全 byte 比較 に加え、普通の
   producer `.kklib` と別 consumer を本当に生成して走らせる。producer の
   public main／ObservedChars metadata を確認し、全 regular-file hashes を
   前後照合する。consumer は実 fresh stdlib と普通の producer をそれぞれ
   読む。ユーザー library を stdlib と偽装しない。
3. 外側 watchdog は direct lane compile 180／run 10／whole 240 秒、ordinary
   producer/consumer は各 compile 180／run 10／whole 420 秒を目安に設定する。
   Swift test 内の compiler call は外側で有限化する。SwiftPM は同一 worktree
   で重ねない。原始 streams／argv／PID/SID/PGID/start identity／timeouts／
   wait/reap と compiler／resources／Runtime ABI／artifact hashes を採取する。
   実際にリンクした Runtime object cache も hash 証明する。採取できない範囲は
   source hash と同一視せず limit として残す。
   Backend helper は decoded UTF-8 streams だけなので任意 raw bytes と称さない。
4. KUU-1727 の actual runner が使える段階で、まず元 Utf839、次に選択 877
   original IDs を source／fresh library O0／O2、test-body library→separate
   consumer O0／O2 で実行する。必要な official reference ID mapping が揃う
   まで paired PASS を付けない。全 877 は他の source/sink API も含むため
   残る前提 blocker を UTF-8 の合格や API unsupported に読み替えない。
   元 driver は Throwable を event として保存するため program exit 0 だけで
   合格にしない。exact ID set、各 BEGIN/PASS 一回、FAIL／重複／欠落なし、
   assertions 実完了と consumer の実 exit を確認する。

first failure/timeout で停止し、実 FAIL／NOT_FINISHED／NOT_RUN を保存する。
FAIL の source／executable／producer は保持する。成功時だけ owned artifacts を
hash／raw／receipt 保存後に削除できる。共有 stdlib cache は削除しない。
現時点の Core／Backend／candidate／Kotlin Native は全て未実行である。
