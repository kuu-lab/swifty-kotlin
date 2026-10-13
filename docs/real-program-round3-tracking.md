# 公開 Kotlin 実プログラム 第3弾の互換性追跡

親チケット: [KUU-1888](https://linear.app/kuu/issue/KUU-1888)

この文書は子チケット、修正PR、原本consumerの残障害と検証不足を対応付ける。
個別の修正は **1子チケット = 1 task = 1 branch = 1 PR** とし、親の追跡更新だけで
コンパイラの互換性が解消したとは扱わない。最新の状況と各再現の契約はLinearを参照する。

## 作成時の基準

2026-10-12の固定証跡は、master
[`a4cb8a64a0fa96bb2e507937dcdd4b85ad4116ed`](https://github.com/kuu-lab/swifty-kotlin/commit/a4cb8a64a0fa96bb2e507937dcdd4b85ad4116ed)
とfresh bundled stdlib `.kklib` を候補にした履歴である。参照はKotlin 2.3.10、
通常JDK API17、Klox原本のみAPI21。原本consumerと、自作の縮小再現・変更した対照を区別する。

| 原本consumerの結果 | 件数 |
|---|---:|
| native O0と参照が一致 | 34 |
| native O0のcompile失敗 | 33 |
| native O0のrun失敗 | 2 |
| 参照consumer自体の失敗（起票対象外） | 1 |
| 合計 | 70 |

修正チケットは当初34件。第1弾の[KUU-1854](https://linear.app/kuu/issue/KUU-1854)配下6件、
第2弾の[KUU-1861](https://linear.app/kuu/issue/KUU-1861)配下10件と合わせて50件だった。
ケース数とチケット数は一致しない。当初34件の縮小再現はO0/O2で障害を確認したが、
原本70件のO2全件検証は実施していない。この集計は現在のmasterの成功数ではない。

ローカルの固定証跡は以下に保存されている。共有リポジトリにはこのbundleを同梱していない。

```text
/Users/kuu/Documents/Codex/2026-10-12/swifty-kotlin-kotlin-linear-ticket/work/round3/evidence-final/
```

監査では `round3-linear-tickets.json` の34 IDを子一覧と照合し、
`original-consumer-results.json` の70件を上表のとおり再集計した。
`recorded-results.json` はreference150 / native-O0 150 / native-O2 57の357レコード。
O2の57レコードを原本70件の検証完了と読み替えない。
再実行時はbundleを複製し、元のsource、command、stdout/stderr、exitの記録を上書きしない。

## 子チケットとPRの状態

**確認時刻: 2026-10-13 08:22 JST。** Linearの子一覧・添付PRとGitHubのstate、
head、checks、queue entry、auto-mergeを取得した時点のスナップショットである。
この監査ではcompiler実行・回帰テストを再実行していない。

直接の子は39件。当初34件（KUU-1889〜1923、別件のKUU-1904を除く）に、
残障害5件（KUU-1925、1927、1930、1931、1932）が加わった。
LinearはDone22件 / In Progress17件、対応PRはMERGED22件 / OPEN7件 / 添付PRなし10件。

OPEN7件のうちqueue entryあり6件、auto-merge有効・queue entryなし1件。Draftは0件。
queue entryはAWAITING_CHECKS4件、MERGEABLE1件、UNMERGEABLE1件。
KUU-1915 / #8759はUNMERGEABLEであり、entryの存在をマージ可能との判定に使わない。
PR head checksは6件SUCCESS / 1件PENDING。PR headとmerge queueのchecks、
PRのMERGED状態、子の完了条件はそれぞれ別の事実である。

| 子 | Linear | PR | GitHub状態 / queue | head checks | 照合head |
|---|---|---|---|---|---|
| [KUU-1889](https://linear.app/kuu/issue/KUU-1889) | Done | [#8765](https://github.com/kuu-lab/swifty-kotlin/pull/8765) | MERGED | SUCCESS | `bcd3ff0a8ba6` |
| [KUU-1890](https://linear.app/kuu/issue/KUU-1890) | In Progress | [#8770](https://github.com/kuu-lab/swifty-kotlin/pull/8770) | OPEN / queue: AWAITING_CHECKS | SUCCESS | `4ae36e8f7882` |
| [KUU-1891](https://linear.app/kuu/issue/KUU-1891) | Done | [#8749](https://github.com/kuu-lab/swifty-kotlin/pull/8749) | MERGED | SUCCESS | `4f1d7be10ef1` |
| [KUU-1892](https://linear.app/kuu/issue/KUU-1892) | In Progress | — | 添付PRなし | — | — |
| [KUU-1893](https://linear.app/kuu/issue/KUU-1893) | Done | [#8758](https://github.com/kuu-lab/swifty-kotlin/pull/8758) | MERGED | SUCCESS | `33732a1e9ddd` |
| [KUU-1894](https://linear.app/kuu/issue/KUU-1894) | Done | [#8757](https://github.com/kuu-lab/swifty-kotlin/pull/8757) | MERGED | SUCCESS | `5c60eea56f7c` |
| [KUU-1895](https://linear.app/kuu/issue/KUU-1895) | In Progress | [#8779](https://github.com/kuu-lab/swifty-kotlin/pull/8779) | OPEN / auto-merge待機 | PENDING | `78f4ebf6d8a4` |
| [KUU-1896](https://linear.app/kuu/issue/KUU-1896) | Done | [#8746](https://github.com/kuu-lab/swifty-kotlin/pull/8746) | MERGED | SUCCESS | `24c977b3b193` |
| [KUU-1897](https://linear.app/kuu/issue/KUU-1897) | Done | [#8754](https://github.com/kuu-lab/swifty-kotlin/pull/8754) | MERGED | SUCCESS | `ae130a4fe564` |
| [KUU-1898](https://linear.app/kuu/issue/KUU-1898) | Done | [#8741](https://github.com/kuu-lab/swifty-kotlin/pull/8741) | MERGED | SUCCESS | `58d03c4e5e52` |
| [KUU-1899](https://linear.app/kuu/issue/KUU-1899) | In Progress | [#8780](https://github.com/kuu-lab/swifty-kotlin/pull/8780) | OPEN / queue: AWAITING_CHECKS | SUCCESS | `4c29893c5adb` |
| [KUU-1900](https://linear.app/kuu/issue/KUU-1900) | In Progress | [#8767](https://github.com/kuu-lab/swifty-kotlin/pull/8767) | OPEN / queue: AWAITING_CHECKS | SUCCESS | `31c5f23ab329` |
| [KUU-1901](https://linear.app/kuu/issue/KUU-1901) | Done | [#8768](https://github.com/kuu-lab/swifty-kotlin/pull/8768) | MERGED | SUCCESS | `dc3028165955` |
| [KUU-1902](https://linear.app/kuu/issue/KUU-1902) | Done | [#8761](https://github.com/kuu-lab/swifty-kotlin/pull/8761) | MERGED | SUCCESS | `a7750bfc265a` |
| [KUU-1903](https://linear.app/kuu/issue/KUU-1903) | In Progress | — | 添付PRなし | — | — |
| [KUU-1905](https://linear.app/kuu/issue/KUU-1905) | Done | [#8740](https://github.com/kuu-lab/swifty-kotlin/pull/8740) | MERGED | SUCCESS | `235c82eb0856` |
| [KUU-1906](https://linear.app/kuu/issue/KUU-1906) | In Progress | — | 添付PRなし | — | — |
| [KUU-1907](https://linear.app/kuu/issue/KUU-1907) | Done | [#8682](https://github.com/kuu-lab/swifty-kotlin/pull/8682) | MERGED | SUCCESS | `470eac10b7bb` |
| [KUU-1908](https://linear.app/kuu/issue/KUU-1908) | Done | [#8766](https://github.com/kuu-lab/swifty-kotlin/pull/8766) | MERGED | SUCCESS | `d7e9a4f0ad32` |
| [KUU-1909](https://linear.app/kuu/issue/KUU-1909) | Done | [#8677](https://github.com/kuu-lab/swifty-kotlin/pull/8677) | MERGED | SUCCESS | `2624f01677a9` |
| [KUU-1910](https://linear.app/kuu/issue/KUU-1910) | Done | [#8745](https://github.com/kuu-lab/swifty-kotlin/pull/8745) | MERGED | SUCCESS | `c26cd1c31db0` |
| [KUU-1911](https://linear.app/kuu/issue/KUU-1911) | Done | [#8701](https://github.com/kuu-lab/swifty-kotlin/pull/8701) | MERGED | SUCCESS | `2d499affa96c` |
| [KUU-1912](https://linear.app/kuu/issue/KUU-1912) | Done | [#8748](https://github.com/kuu-lab/swifty-kotlin/pull/8748) | MERGED | SUCCESS | `57bbd757786f` |
| [KUU-1913](https://linear.app/kuu/issue/KUU-1913) | In Progress | — | 添付PRなし | — | — |
| [KUU-1914](https://linear.app/kuu/issue/KUU-1914) | Done | [#8739](https://github.com/kuu-lab/swifty-kotlin/pull/8739) | MERGED | SUCCESS | `571e6e5327b1` |
| [KUU-1915](https://linear.app/kuu/issue/KUU-1915) | In Progress | [#8759](https://github.com/kuu-lab/swifty-kotlin/pull/8759) | OPEN / queue: UNMERGEABLE | SUCCESS | `f6828f238a68` |
| [KUU-1916](https://linear.app/kuu/issue/KUU-1916) | Done | [#8679](https://github.com/kuu-lab/swifty-kotlin/pull/8679) | MERGED | SUCCESS | `44f031928800` |
| [KUU-1917](https://linear.app/kuu/issue/KUU-1917) | In Progress | [#8771](https://github.com/kuu-lab/swifty-kotlin/pull/8771) | OPEN / queue: MERGEABLE | SUCCESS | `b641e4ccf85e` |
| [KUU-1918](https://linear.app/kuu/issue/KUU-1918) | In Progress | — | 添付PRなし | — | — |
| [KUU-1919](https://linear.app/kuu/issue/KUU-1919) | Done | [#8762](https://github.com/kuu-lab/swifty-kotlin/pull/8762) | MERGED | SUCCESS | `052bd81146a9` |
| [KUU-1920](https://linear.app/kuu/issue/KUU-1920) | In Progress | [#8781](https://github.com/kuu-lab/swifty-kotlin/pull/8781) | OPEN / queue: AWAITING_CHECKS | SUCCESS | `bb521e676751` |
| [KUU-1921](https://linear.app/kuu/issue/KUU-1921) | Done | [#8744](https://github.com/kuu-lab/swifty-kotlin/pull/8744) | MERGED | SUCCESS | `8803a532047c` |
| [KUU-1922](https://linear.app/kuu/issue/KUU-1922) | Done | [#8702](https://github.com/kuu-lab/swifty-kotlin/pull/8702) | MERGED | SUCCESS | `2633a77c7e60` |
| [KUU-1923](https://linear.app/kuu/issue/KUU-1923) | Done | [#8764](https://github.com/kuu-lab/swifty-kotlin/pull/8764) | MERGED | SUCCESS | `f27d6839c478` |
| [KUU-1925](https://linear.app/kuu/issue/KUU-1925) | In Progress | — | 添付PRなし | — | — |
| [KUU-1927](https://linear.app/kuu/issue/KUU-1927) | In Progress | — | 添付PRなし | — | — |
| [KUU-1930](https://linear.app/kuu/issue/KUU-1930) | In Progress | — | 添付PRなし | — | — |
| [KUU-1931](https://linear.app/kuu/issue/KUU-1931) | In Progress | — | 添付PRなし | — | — |
| [KUU-1932](https://linear.app/kuu/issue/KUU-1932) | In Progress | — | 添付PRなし | — | — |

「添付PRなし」はLinearの添付と今回のGitHub検索で対応PRを確認できなかったことを示す。
別のworktreeで実装が進んでいないとの断定ではない。

## 完了判定に残す検証不足

以下は確認したPR本文に記録された不足である。MERGED / Doneから未実行の成功を推定しない。
子に保存された障害時の参照出力だけでは、修正後の同条件検証を満たさない。

| 子 / 証跡 | 未確認または不一致 | 次に確認する範囲 |
|---|---|---|
| KUU-1907 / [#8682](https://github.com/kuu-lab/swifty-kotlin/pull/8682) | source実行180秒・artifact生成600秒でtimeout、fresh artifact未生成。参照は2.4.20 / JRE27 | 2.3.10 / API17でFactorialBigWithCache原本・縮小再現のsource / fresh artifact × O0/O2 |
| KUU-1914 / [#8739](https://github.com/kuu-lab/swifty-kotlin/pull/8739) | 既存artifactのmanifest一致を確認したがfresh生成未完了 | fresh artifactでtuple原本・縮小再現のO0/O2 |
| KUU-1894 / [#8757](https://github.com/kuu-lab/swifty-kotlin/pull/8757) | `lambda_it_destructuring` Goldenの戻り型表示に `Int → Any?` の2行不一致、未変更master比較未実施 | Golden差分の帰属・仕様準拠。縮小再現の成功とは区別 |
| KUU-1920 / [#8781](https://github.com/kuu-lab/swifty-kotlin/pull/8781) | DeclarationBoundaryTestsは30/32成功、prefix-lookahead2件のbase比較未実施 | 2件の失敗をbaseと比較し、constructor変更との関係を確認 |
| KUU-1921 / [#8744](https://github.com/kuu-lab/swifty-kotlin/pull/8744) | 初回23/24成功。atomicfu宣言重複の1件は静的調査のみ、最終ゲートから除外 | 旧HEAD実行との比較。除外したケースをPASSに数えない |
| KUU-1915 / [#8759](https://github.com/kuu-lab/swifty-kotlin/pull/8759) | unchanged Grammar.ktの `tokenizer by lazy` はSEMA-0103で停止 | direct getterへの変更対照と原本を分け、原本を再検証 |
| KUU-1905 / [#8740](https://github.com/kuu-lab/swifty-kotlin/pull/8740) | 広域callable-referenceフィルタは長時間化して中断 | focused結果と中断した範囲を分けて報告 |

参照版が指定の2.3.10と異なることを明記したPRもある。

| 子 | PR | 記録された参照環境 |
|---|---|---|
| KUU-1890 | [#8770](https://github.com/kuu-lab/swifty-kotlin/pull/8770) | Kotlin 2.4.20 / JDK21 |
| KUU-1898 | [#8741](https://github.com/kuu-lab/swifty-kotlin/pull/8741) | Kotlin 2.4.20 / JDK21 |
| KUU-1908 | [#8766](https://github.com/kuu-lab/swifty-kotlin/pull/8766) | Kotlin 2.4.20 / JDK27 |
| KUU-1909 | [#8677](https://github.com/kuu-lab/swifty-kotlin/pull/8677) | 単体diffはKotlin 2.4.20 / JDK27、準備済みartifact再利用 |
| KUU-1919 | [#8762](https://github.com/kuu-lab/swifty-kotlin/pull/8762) | Kotlin 2.4.20 / JDK21 |
| KUU-1922 | [#8702](https://github.com/kuu-lab/swifty-kotlin/pull/8702) | Kotlin 2.4.20 / JRE27 |

これらの参照版差を残し、指定環境での追試を行う。
PR本文にfresh生成や4経路の証跡がなければ未確認として保持する。
その他の子についても、この監査だけで完了条件をすべて満たしたとは認定していない。

## 原本consumerと残障害の対応

各PRの原本残差は、そのbaseとheadで観測した結果である。
複数PRを統合した現在のmasterで残っているかは、同一原本で再検証する必要がある。

| 対象 | 局所修正 | 原本の残障害・検証境界 |
|---|---|---|
| AoC Day20 | KUU-1895のPair / Map value型推論 | [KUU-1925](https://linear.app/kuu/issue/KUU-1925): Map.values.forEachの未定義 `_forEach` |
| AoC Day21 | KUU-1891のArray API、KUU-1912のbuilder型推論 | [KUU-1924](https://linear.app/kuu/issue/KUU-1924): tailrec偽警告、[KUU-1926](https://linear.app/kuu/issue/KUU-1926): Collection.count未束縛、[KUU-1928](https://linear.app/kuu/issue/KUU-1928): source modeのindexedAssign、[KUU-1929](https://linear.app/kuu/issue/KUU-1929): cross-file extension推論 |
| AoC Day17 | KUU-1897のPriorityQueue | [KUU-1933](https://linear.app/kuu/issue/KUU-1933): fresh libraryのprivate State汚染、[KUU-1869](https://linear.app/kuu/issue/KUU-1869): private Comparable。原本4経路は当該PRの検証でcompile停止 |
| AoC Day18 | KUU-1894の混在lambda分解引数 | KUU-1921に関連するcompanion推論残差と[KUU-1927](https://linear.app/kuu/issue/KUU-1927)の関数式本体境界を分ける。原本4経路は当該PRの検証でcompile停止 |
| simple-json | KUU-1911のSAM推論、KUU-1896のwhen join | [KUU-1930](https://linear.app/kuu/issue/KUU-1930): 星射影の2段map、[KUU-1931](https://linear.app/kuu/issue/KUU-1931): member extension parse、[KUU-1932](https://linear.app/kuu/issue/KUU-1932): specialCharactersのany。原本35ソースは当該PRの4経路でcompile停止 |
| better-parse | tuple、delegate、zip、JVM APIなど各子の境界 | KUU-1913 / 1915 / 1917 / 1918 / 1919 / 1920など。tuple単体や変更したGrammar対照の成功を数式・論理式デモ全体の成功にしない |
| Klox / Kotlox | Stack、exception、enum import、File、Systemなど | KUU-1898 / 1899 / 1900 / 1901 / 1902 / 1903 / 1923など。各APIの診断解消とCLI全体の実行を分ける |

KUU-1927のprivate-member最小再現は、master [#8699](https://github.com/kuu-lab/swifty-kotlin/pull/8699)
を含む公開HEADでfresh artifact / O0の成功が子本文に追記済み。
旧baseの失敗を根拠に再実装せず、source / O2と後続宣言の境界回帰を先に確認する。
KUU-1932の独立縮小と他診断との因果関係は未確定である。

追加の独立境界として
[KUU-1934](https://linear.app/kuu/issue/KUU-1934)（同名関数型factoryとSAM constructor）、
[KUU-1942](https://linear.app/kuu/issue/KUU-1942)（expect/actual enum helperのlink failure）も追跡する。
1924 / 1926 / 1928 / 1929 / 1933 / 1934 / 1942は直接の39子の件数に含めない。
既存チケットの独立した修正範囲を維持し、親PRへcompiler修正をまとめない。

## 更新・完了の判断

1. Linearの子一覧と添付PRを取り直し、当初34 ID、追加の子、関連する別件を照合する。
2. GitHubのPR state、head SHA、head checks、queue entry、auto-mergeを取得し、確認時刻を付ける。
3. 原本・縮小再現・成功対照の入力bytes、入力file順、API、参照版を保持する。
4. source stdlib / 同じcompilerで生成したfresh `.kklib` × O0/O2で、
   compile/runのstdout・stderr・exitを同じ参照条件と比較する。
   検証条件は各子の完了条件に従い、子に特有の正負境界も保持する。
5. 別blockerで原本が停止した場合は、関連する既存チケットと未到達の実行を記録する。
   診断数の減少、変更した対照、collectorのexit0だけを原本PASSにしない。
6. 検証不足と原本残差を確認してから親の完了を判断する。追跡文書のPRは親をcloseしない。

今回の変更は文書のみ。compiler / runtime / stdlibの修正、
原本70件の再実行、全Swift tests / 全Golden / 全diff corpusは行っていない。
