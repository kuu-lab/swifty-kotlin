package kotlin.text

import kotlin.internal.KsSymbolName

// KSP-486: MatchResult / MatchGroupCollection / MatchGroup / MatchResult.Destructured
// を Kotlin ソース化する。移行元は Sources/Runtime/RuntimeRegex.swift の
// kk_match_result_* / kk_match_group_* / kk_match_result_destructured_* アクセサ群。
//
// ネイティブに残すのはマッチ位置データの取得（グループ数・値・UTF-16 オフセット・
// 名前付きグループの索引）と、正規表現エンジンによる次マッチ探索のみ。公開 API の
// ロジック（IntRange の組み立て、groupValues のリスト化、コレクション境界チェック、
// destructuring の componentN）はすべてこのファイルにある。

/** マッチが持つグループ数（グループ 0 = マッチ全体を含む）。 */
@KsSymbolName("__kk_match_result_group_count")
private external fun __kkMatchResultGroupCount(match: MatchResult): Int

/** グループ [index] の文字列。存在しないグループでは空文字列。 */
@KsSymbolName("__kk_match_result_group_value")
private external fun __kkMatchResultGroupValue(match: MatchResult, index: Int): String

/** グループ [index] の開始 UTF-16 オフセット。不参加グループでは -1。 */
@KsSymbolName("__kk_match_result_group_start")
private external fun __kkMatchResultGroupStart(match: MatchResult, index: Int): Int

/** グループ [index] の終端 UTF-16 オフセット（閉区間）。不参加グループでは -1。 */
@KsSymbolName("__kk_match_result_group_end")
private external fun __kkMatchResultGroupEnd(match: MatchResult, index: Int): Int

/** 名前付きグループ [name] のグループ番号。未定義または不参加なら -1。 */
@KsSymbolName("__kk_match_result_group_index_of_name")
private external fun __kkMatchResultGroupIndexOfName(match: MatchResult, name: String): Int

/** 直前のマッチの終端以降を正規表現エンジンで再探索する。 */
@KsSymbolName("__kk_match_result_next_match")
private external fun __kkMatchResultNextMatch(match: MatchResult): MatchResult?

private fun matchGroupAt(match: MatchResult, index: Int): MatchGroup? {
    if (index < 0 || index >= __kkMatchResultGroupCount(match)) {
        return null
    }
    val start = __kkMatchResultGroupStart(match, index)
    if (start < 0) {
        return null
    }
    return MatchGroup(__kkMatchResultGroupValue(match, index), start..__kkMatchResultGroupEnd(match, index))
}

/** 単一のキャプチャグループにマッチした文字列とその範囲。 */
public class MatchGroup internal constructor(
    public val value: String,
    public val range: IntRange
)

/** マッチのキャプチャグループ列。インデックスと名前の双方で参照できる。 */
public class MatchGroupCollection internal constructor(private val match: MatchResult) {
    public val size: Int
        get() = __kkMatchResultGroupCount(match)

    public operator fun get(index: Int): MatchGroup? = matchGroupAt(match, index)

    public operator fun get(name: String): MatchGroup? = matchGroupAt(match, __kkMatchResultGroupIndexOfName(match, name))
}

/** 正規表現の 1 回分のマッチ結果。 */
public class MatchResult private constructor() {
    /** マッチした文字列全体。 */
    public val value: String
        get() = __kkMatchResultGroupValue(this, 0)

    /** 入力文字列中でマッチが占める範囲（閉区間）。 */
    public val range: IntRange
        get() = __kkMatchResultGroupStart(this, 0)..__kkMatchResultGroupEnd(this, 0)

    /** グループ 0（マッチ全体）から始まる各グループの文字列。 */
    public val groupValues: List<String>
        get() {
            val values = mutableListOf<String>()
            val count = __kkMatchResultGroupCount(this)
            var index = 0
            while (index < count) {
                values.add(__kkMatchResultGroupValue(this, index))
                index += 1
            }
            return values
        }

    /** キャプチャグループのコレクション。 */
    public val groups: MatchGroupCollection
        get() = MatchGroupCollection(this)

    /** キャプチャグループの分解宣言用ラッパー。 */
    public val destructured: Destructured
        get() = Destructured(this)

    public operator fun component1(): String = __kkMatchResultGroupValue(this, 0)

    public operator fun component2(): String = __kkMatchResultGroupValue(this, 1)

    /** 同じ入力に対する次のマッチ。存在しなければ null。 */
    public fun next(): MatchResult? = __kkMatchResultNextMatch(this)

    /** `val (a, b) = match.destructured` 形式でキャプチャグループを取り出す。 */
    public class Destructured internal constructor(public val match: MatchResult) {
        public operator fun component1(): String = __kkMatchResultGroupValue(match, 1)

        public operator fun component2(): String = __kkMatchResultGroupValue(match, 2)

        public operator fun component3(): String = __kkMatchResultGroupValue(match, 3)

        public operator fun component4(): String = __kkMatchResultGroupValue(match, 4)

        public operator fun component5(): String = __kkMatchResultGroupValue(match, 5)

        public operator fun component6(): String = __kkMatchResultGroupValue(match, 6)

        public operator fun component7(): String = __kkMatchResultGroupValue(match, 7)

        public operator fun component8(): String = __kkMatchResultGroupValue(match, 8)

        public operator fun component9(): String = __kkMatchResultGroupValue(match, 9)
    }
}
