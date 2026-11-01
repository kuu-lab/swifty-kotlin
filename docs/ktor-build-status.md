# Ktor ビルド対応の現状

Ktor をこのコンパイラでビルドできるようにする作業の記録。`Scripts/ktor_build.sh` で追跡できる
再現ハーネスと、このPRで直した false positive、まだ残っているギャップをまとめる。

## 対象と手法

Ktor 3.6.0 の中核3モジュール（`ktor-io` / `ktor-utils` / `ktor-http`、いずれも `common` ソースセットのみ）
と、その依存である kotlinx-io 0.9.1（`core` + `bytestring`）を GitHub からスパースチェックアウトし、
`kswiftc --emit library` でコンパイルして診断コードの分布を見た。実行はコンパイルまでで、リンク・実行は
していない（`common` ソースセットは実行可能な `main` を持たないため）。

```bash
bash Scripts/ktor_build.sh                  # 取得 + 4モジュールをコンパイルし集計
bash Scripts/ktor_build.sh --no-fetch        # 既存チェックアウトを再利用
bash Scripts/ktor_build.sh --module ktor_io  # 1モジュールだけ
```

## このPRで修正したコンパイラのバグ

すべて `kotlinc` 実機と比較して確認済み。`Scripts/diff_cases/` に再現ケースを追加した
（`expect_actual_class_member_body.kt` は kotlinc が単一ファイルでの expect/actual 併存を許さない
ため diff_kotlinc.sh では検証できず、focused Sema test で診断が出ないことを確認）。

**パーサ / AST 構築**

- `context` という名前のパラメータ／プロパティが複数行のパラメータリストの先頭に来ると、
  コンテキストパラメータ宣言だと誤認して宣言の切れ目とみなしていた
  （`context_param_name_multiline.kt`）。
- `fun (() -> R).name()` のような括弧付き関数型レシーバの拡張関数宣言をパースできなかった
  （パースはできるようになったが、`this()` 呼び出しの Sema 解決は未対応。下記「既知のギャップ」参照）。
- infix 演算子名（`or`/`and`/`shl` 等）や `if (...)`/`when (...)` の条件式の直後で改行すると、
  文の切れ目と誤認して後続を破棄していた（`infix_operator_newline_continuation.kt`,
  `if_condition_body_next_line.kt`）。3項以上の infix チェーンが2項目までしか結合されない、
  という特に見つけにくい形で症状が出ていた。
- `.`/`?.`/`?:`/`&&`/`||` で始まる行や `else`/`catch`/`finally` で始まる行の直前で改行すると、
  宣言本体の継続と認識できず切り詰めていた（`cookie_lambda_chain.kt` のようなメソッドチェーン）。
- `typealias A = B` の右辺検索が、`=` を含む名前付き引数を持つ先頭アノテーション
  （`@Deprecated(..., replaceWith = ReplaceWith(...))`）の中の `=` に引っ張られていた。
- `when` 分岐の条件に `in`/`!in`（範囲・コレクションの所属チェック）を書けなかった
  （`Unresolved reference 'in'` になっていた）。
- when 分岐の本体が波括弧なしの代入文（`1 -> x = 10`、`counter += 1` 等）のとき、式パーサが
  代入を式として扱えず本体を「x」の1トークンだけに切り詰め、続く行が新しい（誤った）分岐条件として
  再解釈されて `Unresolved reference 'else'` 等の連鎖エラーになっていた
  （`when_branch_bare_assignment.kt`）。deferred-init な `val` を各 when 分岐で代入する、
  ステートマシン的によく使うパターンが影響を受けていた。

**KIR lowering**

- `when` 分岐の `in`/`!in` 条件は、パースできるようになった後も lowering 側で
  「subject と分岐値の `==` 比較」に変換されてしまい、範囲チェックの結果ではなく
  `subject == (subject in range)`（Int と Bool の比較）相当の壊れたコードを生成していた
  （`when_in_range_condition.kt`）。

**Sema**

- `const val` の畳み込みがリテラル単体にしか対応しておらず、`1024 * 1024` のような二項演算や
  `'\r'.code.toByte()` のような変換チェーン、文字列連結を畳み込めなかった
  （`const_val_folded_expressions.kt`）。
- `expect` class/interface/object のメンバがボディなしで宣言されていると
  「本体が必要」エラーになっていた。`actual` 側が実装を提供する契約であることを認識していなかった
  （`expect_actual_class_member_body.kt`）。
- 拡張関数の本体内で `this@関数名` を書いても、その関数自身の名前をラベルとして解決できなかった
  （`qualified_this_extension_function.kt`）。
- `when` 文（式として値を使わない場合）の網羅性チェックが、Boolean・enum・sealed 以外の subject
  （`Byte` 等）でも常に必須になっていた。kotlinc は文としての `when` はこれらの型に限って
  網羅性を要求する（`when_statement_non_exhaustive_byte.kt`、実機で確認済み）。
- `if`/`when` の分岐の definite assignment 伝播が、`return`/`throw`/`break`/`continue` で終わる
  分岐（`Nothing` 型）を「初期化されなかった」として扱っていた。そうした分岐は正常終了しないので、
  初期化要件を空虚に満たすべき（`definite_assignment_terminating_branches.kt`）。

## 既知のギャップ（このPRでは対応していない）

advisor のレビューに基づき、範囲を絞るために意図的に見送った項目。それぞれ再現ケースで確認済み。

1. **kotlinx.io / kotlinx.serialization / atomicfu の API 面** — `Buffer`/`Source`/`Sink`、
   `atomic()`、`@Serializable` はバンドル stdlib に実装がなく、Ktor/kotlinx-io の大半のファイルが
   これで止まる。バンドル stdlib への追加が必要で、単独の大きめの PR が必要。
2. **kotlinx.coroutines の API 面** — `Job`/`Deferred`/`launch`/`Dispatchers` 等、フルの coroutines
   API はまだ synthetic レジストリの一部のみ。Ktor の非同期コードの大半がこれに依存する。
3. **関数型を拡張レシーバに取る呼び出し規約** — `fun (() -> R).name()` はパースできるようになったが、
   本体内で `this()`（レシーバの呼び出し）を Sema が解決できない（`d_fn_receiver` 系リグレッション）。
4. **`Sequence`/`Regex` チェーンの型推論** — `Regex.findAll(...).map { ... }.filter { ... }` のような
   チェーンで `KSWIFTK-TYPE-0001` になるケースがある（cookie ヘッダ解析等）。
5. **expect/actual のコンストラクタ曖昧性** — 同一スコープに `expect class Foo()` と
   `actual class Foo actual constructor()` があると、コンストラクタ呼び出しが `KSWIFTK-SEMA-0003`
   （曖昧なオーバーロード）になる。expect 側を actual 側から除外するフィルタが構築子には効いていない。
6. **`callsInPlace` 契約に基づく definite assignment** — `contract { callsInPlace(block,
   InvocationKind.EXACTLY_ONCE) }` の効果は記録されるが、`run { x = 1 }` のようなラムダ引数内の
   代入を「必ず一度実行される」として definite assignment に反映していない。バンドル stdlib の
   `run`/`let`/`apply` 自体もこの契約を宣言していない。
7. **`typealias` を介したネスト型解決** — `class Outer { class Inner }`; `typealias A = Outer.Inner`
   が `Unresolved type 'Inner'` になる（単純な `typealias B = pkg.Foo` は直っている）。

いずれも Linear に起票する仕組みがこのセッションには無かったため、issue リンクの記載ができていない。
着手する場合は AGENTS.md のルールに従って Linear（team `Kuu` / project「バグバックログ (BUG)」/
label `Bug`）に起票してから進めること。

## 重大な事前条件の不具合（Ktor 対応とは別件）

作業中に、**バンドル Kotlin stdlib 自体が現在の master で自己コンパイルに失敗する**ことを発見した。
`Sources/CompilerCore/Stdlib/kotlin/random/Random.kt` と `.../collections/{Iterables,MapHOF}.kt` の
自己束縛ジェネリクス（`<T, R : Comparable<R>>` 系）が `KSWIFTK-TYPE-0001`/`KSWIFTK-SEMA-0031` で
落ちる。`git checkout -- Sources` した素の状態、`rm -rf .build` からのフルクリーンビルドでも再現する
ため、このPRの変更が原因ではない。

このため以下が現在ブロックされている:

- `swift build` 後に `~/Library/Caches/kswiftk/stdlib/` のロック/キャッシュを消してからの
  `kswiftc --stdlib-only`・既定の（フラグなしの）コンパイル・`--stdlib-from-source` は全て失敗する。
  古いキャッシュが機械上に残っている間は症状が隠れる。
- `Scripts/diff_kotlinc.sh` は `--stdlib-only` の成功を前提にしているため、現状ではどの diff_cases に
  対しても使えない。このPRの `Scripts/diff_cases/*.kt` は代わりに `kotlinc` を直接呼んで実機比較し、
  出力（コンパイル結果・実行結果）が一致することを個別に確認した。

ゴールデンテストは `TestStdlibCache.prepare()` がこの失敗を握り潰し、必要な宣言だけを遅延解決する
別経路にフォールバックするため大半は影響を受けない（Parser golden 17件、および `const_val`/
`expect_actual`/`generic_typealias`/`when_guard`/`when_multi_condition` 等このPRに関係する
Sema golden 11件は個別に確認しクリーン）。ただし Sema golden の全件（779件）を回すと、
コレクション/シーケンス/範囲系の generic-vs-specialized なオーバーロード解決に依存する20件前後で
golden mismatch が出る。これは `git checkout -- Sources` した素の状態でも `--stdlib-only` の
新規ビルドが同じ16エラーで失敗することから、**この PR の変更とは無関係の環境要因**と判断した
（同じ mismatch セットが my-branch/clean-baseline のどちらでも、キャッシュを消した状態で再現する）。

原因は過去PR #6456 で一部修正した `ConstraintSolver.lub()`/`glb()` の弱いフォールバック
（3個以上の非同一・非KClass型境界が混在するとクラス階層を辿らず即座に `Any` にフォールバックする）
の残存範囲だと考えている（詳細は `equal-constraint-lub-glb-pollution-bug` メモリファイル参照）。
別タスクとして spawn_task 済み。

## IO-F03: 固定版 ktor-io macOS consumer（2026-10-16）

PR #9138 で actual-only companion call の解決を修正した。POSIX dispatcher が import する
`kotlinx.coroutines.IO` は PR #9196（KUU-2404）で bundled coroutine source に追加済みである。
その getter は `Dispatchers.IO` を返すため identity を共有する。KUU-2339（PR #9163）の platform-only
supertype 対応も master に入っている。これらを前提に、固定した Ktor source と bundled library を
使う再現ハーネス `Scripts/ktor_io_consumer.sh` を追加した。

入力の pin は次のとおり。スクリプトは Ktor の version catalog と、bundled kotlinx-io の
`upstream-lock.json` に記録された commit を照合する。

| 入力 | 固定値 |
|---|---|
| Ktor 3.6.0 | commit `111c5807d0a9004c8e0f17ae01e12a71aae56a29` |
| kotlinx-io 0.9.1 | commit `362bdc35e159bad6da1e08101c8321792d762281` |
| kotlinx-coroutines 1.11.0 | commit `8564f65764d3d05893cec026c6e94250e2b23874` |
| Kotlin | 2.3.21 |
| atomicfu | 0.33.0 |
| target | `arm64-apple-macosx` |
| `ktor-io` source roots | `common`, `nonJvm`, `jvmAndPosix`, `posix`, `darwin`（63 files） |

```bash
swift build
bash Scripts/ktor_io_consumer.sh
```

スクリプトは Ktor の commit と version catalog を検証し、fresh bundled stdlib `.kklib` を生成する。
5 source roots をまとめて O0/O2 で library compile し、成功後に consumer を compile・link・実行する。
consumer は packet、stream copy、UTF-8 / CRLF / 空行、buffered channel、flush / close / EOF、
cancellation cause、ByteString peek、unsafe buffer read を扱い、各最適化で stdout を期待バイト列と
完全比較する。プロセスの30秒 timeout でハングも検出する。全ログは既定で一時ディレクトリの
`ktor-io-consumer-111c5807/out/` に残る。既知の fresh `.kklib` を使うときは
`KTOR_IO_STDLIB_KKLIB=/path/to/KSwiftKStdlib.kklib` を指定できる。

実行結果: pinned 63-file library compile、consumer compile・link・run、stdout の期待バイト列との
完全比較が O0/O2 ともに PASS する。KUU-2403（PR #9197）、KUU-2415（PR #9278 / #9288）、
KUU-2404（PR #9196）、KUU-2339（PR #9163）はすべて完了済みで、これらを前提に残っていた
`io.ktor.utils.io.pool.DefaultPool` の expect/actual 重複 metadata（KSWIFTK-LIB-0024）と、
bundled `kotlinx.io` クラスを source が shadow した際に imported member が source class に
付け替わる問題（KSWIFTK-SEMA-0014/0024 の多発）も解消した。

なお `Scripts/ktor_build.sh` の kotlinx_io プローブ（上流 kotlinx-io 0.9.1 を bundled stdlib 上に
再コンパイルする）は **エラー 0 件**（warning SEMA-0102×12 のみ）になった。bundled stdlib に vendored された
`kotlinx.io` と上流 source が同名で衝突する問題は、classifier 参照を同 fqName の imported シンボルより
source 側へ優先させる修正、imported 拡張関数を shadow された imported nominal 側へ留める修正、
同 fqName・同消去シグネチャの imported callable を scope 候補から落とす dedup、および
「内側 tier が不可視候補のみ／全候補が不適格のとき call tower を外側 tier へ続行する」フォールスルーで
解消した。

その後 `ktor_build.sh` がモジュール間依存（`kotlinx_io → ktor_io → ktor_utils → ktor_http`）を
`-I <dep>.kklib` で連鎖するようになり、ktor_io は **0 errors** になった。残っていた
`ByteChannel.kt` の `continuation.resumeWith(throwable?.let { Result.failure(it) } ?: RESUME)`
（`KSWIFTK-TYPE-0001`）は、`Result.failure` の型パラメータが戻り値にしか現れないため
call 引数位置で推論不能だったもので、elvis 引数へ「レシーバの型引数で置換した候補パラメータ型」を
文脈期待型として渡す修正で解消した（`ContravariantContinuationConstraintTests` に回帰テストあり）。
ktor_utils は 26 errors、ktor_http は 324 errors まで減少（`io.ktor.utils.io.*` の
kklib リンクと `this[key]!! += v` の parse/sema 対応で大半のカスケードが解消）。

その後の master（`0263706381` 時点）では bundled stdlib が `kotlinx.io.*` を提供するように
なった。上流 kotlinx-io モジュールを `-I` でリンクすると、bundled stdlib が同名
declaration の所有権を持つため上流側がすべて `KSWIFTK-LIB-0031` で無視され、逆に解決が
壊れる（ktor_io で 195 errors）。そのため `module_deps` は kotlinx_io を下流にリンクしない
構成に更新した。この構成での最新計測値:

| モジュール | exit | files | errors | warnings |
|---|---|---|---|---|
| kotlinx_io | 0 | 30 | 0 | 0 |
| ktor_io | 0 | 45 | 0 | 1 |
| ktor_utils | 1 | 55 | 21 | 8 |
| ktor_http | 1 | 62 | 341 | 0 |

- kotlinx_io は上流ソースが完全クリーンにコンパイルできる（旧5件のドリフトは解消）
- ktor_io は引き続き 0 errors。consumer ハーネスも O0/O2 とも PASS
- ktor_utils の残りは、未リンクの上流依存（`kotlinx.serialization` の `KSerializer` /
  `Serializable`）が大半で、実ギャップは SEMA-INFER / TYPE-0001 / SEMA-0308 / SEMA-0104 など数件。
  coroutines 内部 API の `recoverStackTrace` / `isDispatchNeeded`（`CoroutineDispatcher` の
  open member および `kotlinx.coroutines.internal` のトップレベル関数）は KUU-3910 で
  bundled coroutines に追加済み
- ktor_http の 341 は `io.ktor.util.*` 未解決のカスケードが主因（ktor_utils.kklib が
  未生成のため全 import が落ちる）。ktor_utils が通るまで実数はマスクされる

## まとめ

pinned `ktor-io` は consumer まで含めて O0/O2 で動作し、`ktor_build.sh` の ktor_io プローブも
0 errors を維持している。一方で ktor_utils / ktor_http の standalone コンパイルは
依然失敗し、Ktor 全体をビルド可能にするにはさらに大きな作業（kotlinx.serialization /
atomicfu / kotlinx.coroutines のAPI実装、ktor_utils の残存ギャップなど）が必要になる。
