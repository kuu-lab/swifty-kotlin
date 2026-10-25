package kotlin.text

import kotlin.internal.KsSymbolName

// MatchResult / MatchGroup / MatchGroupCollection / MatchResult.Destructured
// public layer, migrated from Sources/Runtime/RuntimeRegex.swift.

public interface MatchResult {
    public class Destructured internal constructor() {}
}

@KsSymbolName("__kk_match_result_group_count")
internal external fun __kkMatchResultGroupCount(match: MatchResult): Int

@KsSymbolName("__kk_match_result_group_value")
internal external fun __kkMatchResultGroupValue(match: MatchResult, index: Int): String

/** UTF-16 offset of the group's first character, or -1 when the group did not participate. */
@KsSymbolName("__kk_match_result_group_start")
internal external fun __kkMatchResultGroupStart(match: MatchResult, index: Int): Int

/** UTF-16 offset of the group's last character (inclusive), or -1 when absent. */
@KsSymbolName("__kk_match_result_group_end")
internal external fun __kkMatchResultGroupEnd(match: MatchResult, index: Int): Int

/** Index of the capture group named [name], or -1 when the match has no such group. */
@KsSymbolName("__kk_match_result_group_index_of_name")
internal external fun __kkMatchResultGroupIndexOfName(match: MatchResult, name: String): Int

@KsSymbolName("__kk_match_result_has_named_group")
internal external fun __kkMatchResultHasNamedGroup(match: MatchResult, name: String): Boolean

@KsSymbolName("__kk_match_result_next")
internal external fun __kkMatchResultNext(match: MatchResult): MatchResult?

@KsSymbolName("__kk_match_result_destructured")
internal external fun __kkMatchResultDestructured(match: MatchResult): MatchResult.Destructured

@KsSymbolName("__kk_match_result_destructured_match")
internal external fun __kkDestructuredMatch(destructured: MatchResult.Destructured): MatchResult

@KsSymbolName("__kk_regex_pattern")
internal external fun __kkRegexPattern(regex: Regex): String

/** Bit mask of the `RegexOption` ordinals the regex was created with. */
@KsSymbolName("__kk_regex_option_mask")
internal external fun __kkRegexOptionMask(regex: Regex): Int

public val Regex.pattern: String
    get() = __kkRegexPattern(this)

public val Regex.options: Set<RegexOption>
    get() {
        val mask = __kkRegexOptionMask(this)
        val result = mutableSetOf<RegexOption>()
        if (mask and 1 != 0) result.add(RegexOption.IGNORE_CASE)
        if (mask and 2 != 0) result.add(RegexOption.MULTILINE)
        if (mask and 4 != 0) result.add(RegexOption.LITERAL)
        if (mask and 8 != 0) result.add(RegexOption.UNIX_LINES)
        if (mask and 16 != 0) result.add(RegexOption.COMMENTS)
        if (mask and 32 != 0) result.add(RegexOption.DOT_MATCHES_ALL)
        if (mask and 64 != 0) result.add(RegexOption.CANON_EQ)
        return result
    }

/** Names of the named capture groups declared by the pattern, in declaration order. */
public val Regex.groupNames: Set<String>
    get() {
        val pattern = __kkRegexPattern(this)
        val names = mutableSetOf<String>()
        var index = 0
        while (index + 3 < pattern.length) {
            if (pattern[index] == '\\') {
                index += 2
                continue
            }
            if (pattern[index] == '(' && pattern[index + 1] == '?' && pattern[index + 2] == '<' &&
                __kkIsGroupNameStart(pattern[index + 3])
            ) {
                val name = StringBuilder()
                var cursor = index + 3
                while (cursor < pattern.length && __kkIsGroupNamePart(pattern[cursor])) {
                    name.append(pattern[cursor])
                    cursor++
                }
                if (cursor < pattern.length && pattern[cursor] == '>') {
                    names.add(name.toString())
                    index = cursor
                }
            }
            index++
        }
        return names
    }

private fun __kkIsGroupNameStart(c: Char): Boolean =
    (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_'

private fun __kkIsGroupNamePart(c: Char): Boolean =
    __kkIsGroupNameStart(c) || (c >= '0' && c <= '9')

public data class MatchGroup(public val value: String, public val range: IntRange)

/**
 * The capture groups of a single match, addressable by index (0 = entire match)
 * or by name for named capture groups. Absent (non-participating) groups read
 * as `null`.
 */
public interface MatchGroupCollection : Collection<MatchGroup?> {
    public override val size: Int

    public operator fun get(index: Int): MatchGroup?

    // Platform implementations expose the named accessor on the base
    // collection type. Keep that existing KSwiftK surface while the
    // source-backed MatchNamedGroupCollection interface provides the
    // corresponding official contract.
    public operator fun get(name: String): MatchGroup?
}

private class MatchGroupCollectionImpl(
    private val match: MatchResult
) : AbstractCollection<MatchGroup?>(), MatchNamedGroupCollection {
    override val size: Int
        get() = __kkMatchResultGroupCount(match)

    override fun get(index: Int): MatchGroup? {
        if (index < 0 || index >= __kkMatchResultGroupCount(match)) return null
        val start = __kkMatchResultGroupStart(match, index)
        if (start < 0) return null
        val end = __kkMatchResultGroupEnd(match, index)
        return MatchGroup(__kkMatchResultGroupValue(match, index), start..end)
    }

    override fun get(name: String): MatchGroup? {
        if (!__kkMatchResultHasNamedGroup(match, name)) {
            throw IllegalArgumentException("No group with name <$name>")
        }
        val index = __kkMatchResultGroupIndexOfName(match, name)
        if (index < 0) return null
        return get(index)
    }

    override fun iterator(): Iterator<MatchGroup?> {
        val collection = this
        return object : Iterator<MatchGroup?> {
            private var index = 0

            override fun hasNext(): Boolean = index < collection.size

            override fun next(): MatchGroup? {
                if (!hasNext()) throw NoSuchElementException()
                return collection[index++]
            }
        }
    }
}

public val MatchResult.value: String
    get() = __kkMatchResultGroupValue(this, 0)

public val MatchResult.range: IntRange
    get() {
        val start = __kkMatchResultGroupStart(this, 0)
        val end = __kkMatchResultGroupEnd(this, 0)
        return start..end
    }

/** The values of all groups: index 0 is the entire match, 1..n the capture groups. */
public val MatchResult.groupValues: List<String>
    get() {
        val count = __kkMatchResultGroupCount(this)
        val values = mutableListOf<String>()
        var index = 0
        while (index < count) {
            values.add(__kkMatchResultGroupValue(this, index))
            index++
        }
        return values
    }

public val MatchResult.groups: MatchGroupCollection
    get() = MatchGroupCollectionImpl(this)

public operator fun MatchResult.component1(): String = __kkMatchResultGroupValue(this, 0)

public operator fun MatchResult.component2(): String = __kkMatchResultGroupValue(this, 1)

public fun MatchResult.next(): MatchResult? = __kkMatchResultNext(this)

public val MatchResult.destructured: MatchResult.Destructured
    get() = __kkMatchResultDestructured(this)

public val MatchResult.Destructured.match: MatchResult
    get() = __kkDestructuredMatch(this)

@PublishedApi
internal fun MatchResult.Destructured.groupValue(index: Int): String =
    __kkMatchResultGroupValue(__kkDestructuredMatch(this), index)

public operator fun MatchResult.Destructured.component1(): String = groupValue(1)

public operator fun MatchResult.Destructured.component2(): String = groupValue(2)

public operator fun MatchResult.Destructured.component3(): String = groupValue(3)

public operator fun MatchResult.Destructured.component4(): String = groupValue(4)

public operator fun MatchResult.Destructured.component5(): String = groupValue(5)

public operator fun MatchResult.Destructured.component6(): String = groupValue(6)

public operator fun MatchResult.Destructured.component7(): String = groupValue(7)

public operator fun MatchResult.Destructured.component8(): String = groupValue(8)

public operator fun MatchResult.Destructured.component9(): String = groupValue(9)

public operator inline fun MatchResult.Destructured.component10(): String = groupValue(10)

public fun MatchResult.Destructured.toList(): List<String> {
    val values = __kkDestructuredMatch(this).groupValues
    return values.subList(1, values.size)
}
