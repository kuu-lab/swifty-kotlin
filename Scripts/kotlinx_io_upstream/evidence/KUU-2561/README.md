# KUU-2561 証跡

## 固定対象

- Upstream: kotlinx-io 0.9.1 / Kotlin 2.3.10 / `362bdc35e159bad6da1e08101c8321792d762281`
- 原本: [`upstream/UnsafeBufferOperationsWriteTest.kt`](upstream/UnsafeBufferOperationsWriteTest.kt)、8151 bytes、SHA-256 `d49a734d0446659692b10032f751b1232ad8c57a8ce58ad4288f9115abf78eda`、Git blob `9e638245ca323a19fc2c464069ed5613802fe1e0`
- 対象 invocation: `writeMultipleBytes` / `resetWriteOnException` / `returnLessBytesThanItWasActuallyWritten`。各3件を JVM・macOS Native reference で実行。継承/factory/parameterized 呼び出しはこの固定カタログにはない。
- 4つの `setUnchecked` arity は `writeMultipleBytes` の両ブロックで全て実行。元 assertion の行範囲と実行IDの対応は [`coverage-map.verified.json`](../../coverage-map.verified.json) に記録。

## 実行結果

JVM reference は3/3 PASS、Kotlin/Native macOS reference は3/3 PASS。candidate は同一SHA `c7b70e8d62bfcd5c1df891ee28d3886ae419414e` / compiler SHA-256 `466800e6ca596ead594ec53fbec8cd37b0f982f5458e5bd02fbea6dc176222a0` で下記6 laneを実行し、各3/3 PASS。個別 `summary.json`、selection、compile/run command・結果、per-ID `results.json` は各laneディレクトリに保存した。

| Candidate lane | 結果 |
| --- | --- |
| source-O0 | 3/3 PASS |
| source-O2 | 3/3 PASS |
| stdlib-library-O0 | 3/3 PASS |
| stdlib-library-O2 | 3/3 PASS |
| producer-consumer-O0 | 3/3 PASS |
| producer-consumer-O2 | 3/3 PASS |

追加の直接観測probeは Kotlin 2.3.10 / JDK 21 reference と candidate source injection が同じ3行を出力することを確認した: `contract-probes/observations-results.json`。出力は両reference/candidateで完全一致する。各write callbackは1回、1〜4 byte overloadと重なり書きは expected bytes と戻り値が一致、2つの例外callbackも各1回実行後にbuffer exhausted。short-writeは42 bytesを要求した領域の8192 bytesを書いて4を返し、committed size 4 / UInt `2880154539` (`0xabababab`) を確認。

## API/ABI 契約

8行の API 証跡は [`api-validation-evidence.json`](../../../io_api_inventory/api-validation-evidence.json) に row ごと登録し、generator で台帳へ適用する。KLIB行は source-O0/O2、fresh stdlib-library-O0/O2、producer-consumer-O0/O2 の6 laneを要求する。4つの JVM descriptor は `reference/SegmentWriteContext.javap.txt` に固定: public abstract `setUnchecked` descriptor `(Lkotlinx/io/Segment;IB)V`, `...IBB)V`, `...IBBB)V`, `...IBBBB)V`。同classのメソッド数は4、`$default` bridgeなし。Kotlin source/KLIB declaration は public、4 overloadとも default parameter/throws contractなし。`UnsafeIoApi` は interface に付与されている。

Candidate fresh KLIB に対する negative/positive opt-in probes は `contract-probes/opt-in-results.json` に保存した。opt-inなしで診断 `KSWIFTK-SEMA-OPT-IN` が5件、`@OptIn(UnsafeIoApi::class)` 付きでは診断0件、どちらもcompile exit 0 (marker levelはWARNING)。

## 歴史的 candidate と対象SHA

Issue description にある過去の candidate `fd01a5e98145e8295e5b299b0a7190cc8d44e3a7` は `baseline-fd01/` に分離保存した。そこではsource-O0 compileは通ったが、runが `KSWIFTK-RUNTIME-0001` (`kk_array_get_inbounds` precondition failure) で exit -5 し、3件とも `NOT_RUN`。これをPASS証跡に流用していない。完了証跡は現在の同一candidate SHA `c7b70e8d62bfcd5c1df891ee28d3886ae419414e` に対する全6 laneのみ。

## 再実行

```sh
PYTHONDONTWRITEBYTECODE=1 python3 Scripts/io_api_inventory/generate.py --write
PYTHONDONTWRITEBYTECODE=1 python3 Scripts/io_api_inventory/generate.py --check
PYTHONDONTWRITEBYTECODE=1 python3 Scripts/io_api_inventory/test_validation_evidence.py
PYTHONDONTWRITEBYTECODE=1 python3 Scripts/kotlinx_io_upstream/tests/test_jvm_reference.py
PYTHONDONTWRITEBYTECODE=1 python3 Scripts/kotlinx_io_upstream/tests/test_native_reference.py
```

`scope-audit.json` は対象3関数・8 API行に blocker がないことを記録する。全体監査は残り677 upstream関数と他API行のためFAILであり、この小チケットの対象外。全repo suiteは実行していない。
