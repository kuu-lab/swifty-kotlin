package kotlin.text

import kotlin.internal.KsSymbolName

// KSP-486: Regex の純データ参照プロパティ（pattern / options / groupNames）を
// Kotlin ソース化する。移行元は Sources/Runtime/RuntimeRegex.swift の
// kk_regex_pattern / kk_regex_options / kk_regex_group_names。
// Regex 本体（生成・find・replace など正規表現エンジンに触れる API）は KSP-487 の対象。

/** コンパイル時に与えられたパターン文字列。 */
@KsSymbolName("__kk_regex_pattern")
private external fun __kkRegexPattern(regex: Regex): String

/** この Regex が保持する RegexOption の ordinal ビットマスク（`1 shl ordinal`）。 */
@KsSymbolName("__kk_regex_option_mask")
private external fun __kkRegexOptionMask(regex: Regex): Int

/** パターン中に現れる名前付きキャプチャグループ名（出現順）。 */
@KsSymbolName("__kk_regex_group_name_list")
private external fun __kkRegexGroupNameList(regex: Regex): List<String>

public val Regex.pattern: String
    get() = __kkRegexPattern(this)

public val Regex.options: Set<RegexOption>
    get() {
        val mask = __kkRegexOptionMask(this)
        val result = mutableSetOf<RegexOption>()
        if ((mask and 1) != 0) result.add(RegexOption.IGNORE_CASE)
        if ((mask and 2) != 0) result.add(RegexOption.MULTILINE)
        if ((mask and 4) != 0) result.add(RegexOption.DOT_MATCHES_ALL)
        if ((mask and 8) != 0) result.add(RegexOption.LITERAL)
        if ((mask and 16) != 0) result.add(RegexOption.UNIX_LINES)
        if ((mask and 32) != 0) result.add(RegexOption.COMMENTS)
        if ((mask and 64) != 0) result.add(RegexOption.CANON_EQ)
        return result
    }

public val Regex.groupNames: Set<String>
    get() {
        val result = mutableSetOf<String>()
        for (name in __kkRegexGroupNameList(this)) {
            result.add(name)
        }
        return result
    }
