# KUU-2644: `Path.hashCode()` 検証記録

## 固定入力

- 候補: `fd01a5e98145e8295e5b299b0a7190cc8d44e3a7`
- 参照: kotlinx-io `0.9.1`、upstream `362bdc35e159bad6da1e08101c8321792d762281`
- upstream の `core/common/test/files/SmokeFileTest.kt` は lock 上で 14,635 bytes、Git blob `db7824e7a348529bcb1cfcde76fbfe92ab0f493f`、SHA-256 `f4093fbdcda4c2027788d824d67d356774ab13ccc0e272793380dc7640479662`。
- 固定 upstream の [`SmokeFileTest.kt`](https://github.com/Kotlin/kotlinx-io/blob/362bdc35e159bad6da1e08101c8321792d762281/core/common/test/files/SmokeFileTest.kt) の `pathEquality` には等値 assertion が 3 件あり、`hashCode()` の直接呼び出しはありません。
- 新しい probe `Scripts/diff_cases/kotlinx_io_path_hashcode.kt`: SHA-256 `689470e79b03421788f21b3f988e188b91ae2b4d90111591c68cce278a709ea0`。`check()` は 10 件。
- 回帰テスト `Tests/CompilerBackendTests/StdlibArtifactRegressionTests+KotlinxIOPathHashCode.swift`: SHA-256 `8435d9468bffef7dd6052376dfb38549fcf766df1b3f98ecf77625d2b7e4fd2c`。
- `generate.py --show-input-hashes` の implementation/test SHA-256 は、それぞれ `e6ccf57cff69d41058d3365989d6339b2d297f6ea839aaf52c1d195847379095` / `bb9c662f127bd41956368e7815f8a6e7d275ac94cad6f9cf37e88c30818ecc9d`。

## 直接確認した内容

Probe は `Path("folder", "leaf")` と同じ文字列を表す `Path("folder/leaf")` を使い、次を直接確認します。

1. `toString()` が `folder/leaf` を返す。
2. `hashCode() == toString().hashCode()`。
3. 同じ文字列表現を持つ `Path` 同士が等しく、hash code も一致する。
4. 等しい Path の HashSet 重複挿入・検索と HashMap lookup が一致する。
5. 異なる Path は HashSet に含まれず、HashMap lookup も存在しない。

実装確認では、KSwiftK の `Sources/CompilerCore/Stdlib/kotlinx/io/files/Paths.kt`（SHA-256 `15afd8083dcb1fc92705c6191c974b42c9df0ad62366fc7f380999daae1604a6`）も `toString() = path`、`hashCode() = path.hashCode()`、`equals` は `path` 同士の比較です。upstream JVM actual は `toString().hashCode()`、Native actual は `path.hashCode()` を返し、common contract は文字列表現に基づく hash/equality を記述しています。

## 参照結果

| 参照 | 結果 | SHA-256 |
|---|---|---|
| Kotlin/JVM 2.3.10、JDK 21、pinned kotlinx-io JVM jars | exit 0、stderr 0 bytes、`path-hashcode:OK\n` | stdout `4ae76a44a4e7c8330e1e350b1bec2e8c8fd2e3e77bba32d8f6976cbe9d081311` |
| Kotlin/Native 2.3.10、macOS ARM64、O0 | exit 0、stderr 0 bytes、`path-hashcode:OK\n` | stdout `4ae76a44a4e7c8330e1e350b1bec2e8c8fd2e3e77bba32d8f6976cbe9d081311`; executable `4ce66e35447537ce7a14b54b6fc7078213ea93f0338a8ed80e4cdb2b7bb3b46f` |
| Kotlin/Native 2.3.10、macOS ARM64、O2 | exit 0、stderr 0 bytes、`path-hashcode:OK\n` | stdout `4ae76a44a4e7c8330e1e350b1bec2e8c8fd2e3e77bba32d8f6976cbe9d081311`; executable `62b5e5e5c3d38ba2561b40c7e4d7d6e84c0a170d4183bb9c5a2e73afc8a91f61` |

Pinned JVM jar の `javap -c -s kotlinx.io.files.Path` では `public int hashCode(); descriptor: ()I` があり、本体は `toString()` の戻り値に `java/lang/String.hashCode()` を呼びます。`javap` 出力の SHA-256 は `dbab9be952f5c02b6723abca2fe01fd1451e24cb8d092fef82c06a15080340c3`。参照 `kotlinx-io-core-jvm-0.9.1.jar` と bytestring jar の SHA-256 はそれぞれ `765d8851d8ca694706931331b92386844800867e041b720f1f193dbda874d370` / `8589de0b7c476bfdd02a24641685f609ade72f5e595cf2909c168acdba7e6ba4`。

## 固定候補での検証

Swift 回帰テストは候補 SHA のコンパイラに fixture/test を適用し、fresh source と fresh KLib の各 O0/O2 を実行しました。4 test cases がすべて PASS（486.432 秒）。初回は隔離環境の SwiftPM Runtime build が `sandbox_apply: Operation not permitted` で失敗したため、候補ソースから独立 Runtime scratch を構築し、manifest 検証済み object cache で再実行しました。

F02 専用実行は HEAD `fd01a5e98145e8295e5b299b0a7190cc8d44e3a7` の checkout で行い、候補 compiler SHA-256 は `9092b21c24a7d433d4faa439f048be542d59610a19d7128e748b0c430abeb984`。Runtime object は同じ候補 checkout から新しい scratch path に build しました。fresh stdlib KLib は候補テストで生成した 1,850-file artifact で、manifest SHA-256 `60db43cee285f7415d24f0210d00d6ca70078e454aac5109b98147a3e1282569`、metadata SHA-256 `5296e1e4f35735fe956a9389c3a299e88e088f61a39b90ea826dc8d559e8a0a7`。

| 経路 | 最適化 | 結果 | 出力 SHA-256 | candidate executable SHA-256 |
|---|---:|---|---|---|
| source | O0 | PASS、exit 0 | `c4d814713a9e7fb20afb07c5bd4c51206aeb2deb5f4d06c79002235f58f15b6c` | `8cab14b0f8a9e2253a1f27af0a4487b2afeef39681ddc064b3c51e84ffbcacd2` |
| source | O2 | PASS、exit 0 | 同上 | `5362eefa59b81f9b22a964d8e4c5af6a0723b247d10bbc473d6fcd965e96eb9` |
| stdlib-library | O0 | PASS、exit 0 | 同上 | `1fd07dd974f3ac83edf0e9847857488a4b625e386a5ae7256f375510ecf5bb86` |
| stdlib-library | O2 | PASS、exit 0 | 同上 | `1ad96891eba912966feee38d8e4c5af6a0723b247d10bbc473d6fcd965e96eb9` |
| producer-consumer | O0 | PASS、producer/consumer とも exit 0 | 同上 | `e3d4d4918bd797372f3e797a1d7a097bb29a7e0749beda3ca695234146479514` |
| producer-consumer | O2 | PASS、producer/consumer とも exit 0 | 同上 | `e18ad903f335f7708c7222b0fc47aa5ffe753b12fb57cf9554e57810cae22abc` |

F02 の JVM reference と全 6 candidate lane の出力は byte-for-byte 一致し、stderr は空です。共通出力は次の 3 行、93 bytes です。

```text
BEGIN-FIXTURE:kotlinx_io_path_hashcode
path-hashcode:OK
END-FIXTURE:kotlinx_io_path_hashcode
```

producer KLib の object SHA-256 は O0 `cd848a01e750b1202968e4dbc879f8a8fcd74f26c50c0e0f25320b11a2d03d36`、O2 `92568920f699e1d13fffedc4cde1ff3dce192391beb58eff7188c45a9d674ddf`。両方の manifest hash は `9715ce5f9d227cd72df1e1704d38e60cbc43652dd10b8b82457542efa637daf3`、metadata hash は `311462a0c54db0ad3037684f96d4d4f7dc86dc78579c12a6525f064a66aa0a7d`。

## 台帳

`api-validation-evidence.json` schema v1 に JVM row `jvm-e537ccd38bc7fca2` と KLIB row `klib-07cfd563616534cf` の PASS を記録しました。KLIB row は 6 F02 lane に加え `macos-apple-reference` を記録しています。この lane の reference は上記 Kotlin/Native O0 probe、candidate は固定候補 source-O0 probe です。`jvm-descriptor` は pinned JVM jar の `javap` 結果で descriptor を確認し、candidate 側は同じ probe の固定候補 source-O0 実行です（KSwiftK は JVM bytecode を出力しないため、その実行は descriptor dump を代替しません）。

`test_validation_evidence.py` は 14 tests PASS、`generate.py --check` は 706 rows / 8 scope rows で deterministic PASS、`git diff --check` も PASS です。全 IO API の F02 matrix と全 Swift test suite はこのチケットでは実行していません。
