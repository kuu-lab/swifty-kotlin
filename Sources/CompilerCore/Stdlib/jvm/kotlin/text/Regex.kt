package kotlin.text
import kotlin.jvm.internal.*
import kotlin.ranges.IntRange
import kotlin.sequences.*
interface FlagEnum { val value: Int; val mask: Int }
enum class RegexOption: FlagEnum { IGNORE_CASE, MULTILINE, LITERAL, UNIX_LINES, COMMENTS, DOT_MATCHES_ALL, CANON_EQ;
    override val value: Int get() = if (this == IGNORE_CASE) 2 else regexFlag(this)
    override val mask: Int get() = if (this == IGNORE_CASE) 2 else regexFlag(this)
}
private fun regexFlag(option: RegexOption): Int = when (option) {
    RegexOption.IGNORE_CASE -> 66
    RegexOption.MULTILINE -> 8
    RegexOption.LITERAL -> 16
    RegexOption.UNIX_LINES -> 1
    RegexOption.COMMENTS -> 4
    RegexOption.DOT_MATCHES_ALL -> 32
    RegexOption.CANON_EQ -> 128
}
private fun regexFlags(options: Set<RegexOption>): Int {
    var flags = 0
    for (option in options) flags = flags or regexFlag(option)
    return flags
}
class Regex private constructor(private val nativePattern: Any) {
    constructor(pattern: String): this(__jvmPattern(pattern, 0))
    constructor(pattern: String, option: RegexOption): this(__jvmPattern(pattern, regexFlag(option)))
    constructor(pattern: String, options: Set<RegexOption>): this(__jvmPattern(pattern, regexFlags(options)))
    val pattern: String get() = __jvmPatternText(nativePattern)
    val options: Set<RegexOption> get() {
        val result = mutableSetOf<RegexOption>()
        val flags = __jvmPatternFlags(nativePattern)
        for (option in RegexOption.values()) if ((flags and (if (option == RegexOption.IGNORE_CASE) 2 else regexFlag(option))) != 0) result.add(option)
        return __jvmUnmodifiableSet(result)
    }
    fun matches(input: CharSequence): Boolean = __jvmMatcherMatches(__jvmMatcher(nativePattern, input))
    fun containsMatchIn(input: CharSequence): Boolean = __jvmMatcherFind(__jvmMatcher(nativePattern, input))
    fun find(input: CharSequence, startIndex: Int = 0): MatchResult? {
        val matcher = __jvmMatcher(nativePattern, input)
        return if (__jvmMatcherFindAt(matcher, startIndex)) MatcherResult(this, input, matcher) else null
    }
    fun findAll(input: CharSequence, startIndex: Int = 0): Sequence<MatchResult> {
        if (startIndex < 0 || startIndex > input.length) throw IndexOutOfBoundsException("Start index out of bounds")
        return generateSequence({ find(input, startIndex) }, { match -> match.next() })
    }
    fun matchEntire(input: CharSequence): MatchResult? {
        val matcher = __jvmMatcher(nativePattern, input)
        return if (__jvmMatcherMatches(matcher)) MatcherResult(this, input, matcher) else null
    }
    fun matchAt(input: CharSequence, index: Int): MatchResult? {
        val matcher = __jvmMatcher(nativePattern, input)
        __jvmMatcherRegion(matcher, index, input.length)
        __jvmMatcherTransparent(matcher, true)
        __jvmMatcherAnchoring(matcher, false)
        return if (__jvmMatcherLookingAt(matcher)) MatcherResult(this, input, matcher) else null
    }
    fun matchesAt(input: CharSequence, index: Int): Boolean = matchAt(input, index) != null
    fun replace(input: CharSequence, replacement: String): String = __jvmMatcherReplaceAll(__jvmMatcher(nativePattern, input), replacement)
    fun replace(input: CharSequence, transform: (MatchResult) -> CharSequence): String {
        val builder = StringBuilder()
        var position = 0
        var match = find(input)
        while (match != null) {
            val current = match!!
            builder.append(input.subSequence(position, current.range.first))
            builder.append(transform(current))
            position = current.range.last + 1
            match = current.next()
        }
        builder.append(input.subSequence(position, input.length))
        return builder.toString()
    }
    fun replaceFirst(input: CharSequence, replacement: String): String = __jvmMatcherReplaceFirst(__jvmMatcher(nativePattern, input), replacement)
    fun split(input: CharSequence, limit: Int = 0): List<String> {
        if (limit < 0) throw IllegalArgumentException("Limit must be non-negative, but was $limit")
        val result = mutableListOf<String>()
        if (limit == 1) { result.add(input.toString()); return result }
        var position = 0
        var match = find(input)
        while (match != null && (limit == 0 || result.size < limit - 1)) {
            val current = match!!
            result.add(input.subSequence(position, current.range.first).toString())
            position = current.range.last + 1
            match = current.next()
        }
        result.add(input.subSequence(position, input.length).toString())
        return result
    }
    fun splitToSequence(input: CharSequence, limit: Int = 0): Sequence<String> {
        if (limit < 0) throw IllegalArgumentException("Limit must be non-negative, but was $limit")
        return object: Sequence<String> {
            override fun iterator(): Iterator<String> = object: Iterator<String> {
                var position = 0
                var searchPosition = 0
                var count = 0
                var state = -1
                var nextText: String? = null
                fun compute() {
                    if (state != -1) return
                    val match = if (searchPosition > input.length || (limit > 0 && count == limit - 1)) null else find(input, searchPosition)
                    if (match == null) {
                        nextText = input.subSequence(position, input.length).toString()
                        state = 2
                    } else {
                        nextText = input.subSequence(position, match.range.first).toString()
                        position = match.range.last + 1
                        searchPosition = position + if (match.range.first == position) 1 else 0
                        state = 1
                    }
                    count++
                }
                override fun hasNext(): Boolean { compute(); return state != 0 }
                override fun next(): String {
                    compute()
                    if (state == 0) throw NoSuchElementException()
                    val result = nextText!!
                    nextText = null
                    state = if (state == 2) 0 else -1
                    return result
                }
            }
        }
    }
    override fun toString(): String = pattern
    companion object {
        fun fromLiteral(literal: String): Regex = Regex(literal, RegexOption.LITERAL)
        fun escape(literal: String): String = __jvmPatternQuote(literal)
        fun escapeReplacement(literal: String): String = __jvmMatcherQuote(literal)
    }
}
interface MatchResult {
    val value: String
    val range: IntRange
    val groups: MatchGroupCollection
    val groupValues: List<String>
    val destructured: Destructured
    class Destructured(val match: MatchResult) {
        operator fun component1(): String = match.groupValues[1]
        operator fun component2(): String = match.groupValues[2]
        operator fun component3(): String = match.groupValues[3]
        operator fun component4(): String = match.groupValues[4]
        operator fun component5(): String = match.groupValues[5]
        operator fun component6(): String = match.groupValues[6]
        operator fun component7(): String = match.groupValues[7]
        operator fun component8(): String = match.groupValues[8]
        operator fun component9(): String = match.groupValues[9]
        operator fun component10(): String = match.groupValues[10]
        fun toList(): List<String> = match.groupValues.drop(1)
    }
    fun next(): MatchResult?
}
data class MatchGroup(val value: String, val range: IntRange)
interface MatchGroupCollection: Collection<MatchGroup?>, Iterable<MatchGroup?> {
    override fun iterator(): Iterator<MatchGroup?>
    operator fun get(index: Int): MatchGroup?
}
private class MatcherGroups(private val matcher: Any): MatchGroupCollection, kotlin.jvm.internal.markers.KMappedMarker {
    override val size: Int get() = __jvmMatcherGroupCount(matcher) + 1
    override fun isEmpty(): Boolean = false
    override fun contains(element: MatchGroup?): Boolean {
        var index = 0
        while (index < size) { if (get(index) == element) return true; index++ }
        return false
    }
    override fun containsAll(elements: Collection<MatchGroup?>): Boolean {
        for (element in elements) {
            if (element != null && !(element is MatchGroup)) return false
            if (!contains(element as MatchGroup?)) return false
        }
        return true
    }
    fun toArray(): Array<Any?> {
        val result = arrayOfNulls<Any?>(size)
        var index = 0
        while (index < size) { result[index] = get(index); index++ }
        return result
    }
    fun <T> toArray(array: Array<T>): Array<T> {
        val result = if (array.size < size) __jvmCopyArray(array, size) else array
        var index = 0
        while (index < size) { result[index] = get(index) as T; index++ }
        if (result.size > size) result[size] = null as T
        return result
    }
    fun add(element: Any?): Boolean = throw UnsupportedOperationException("Operation is not supported for read-only collection")
    fun remove(element: Any?): Boolean = throw UnsupportedOperationException("Operation is not supported for read-only collection")
    fun addAll(elements: Collection<*>): Boolean = throw UnsupportedOperationException("Operation is not supported for read-only collection")
    fun removeAll(elements: Collection<*>): Boolean = throw UnsupportedOperationException("Operation is not supported for read-only collection")
    fun retainAll(elements: Collection<*>): Boolean = throw UnsupportedOperationException("Operation is not supported for read-only collection")
    fun clear() { throw UnsupportedOperationException("Operation is not supported for read-only collection") }
    override fun iterator(): Iterator<MatchGroup?> = object: Iterator<MatchGroup?>, kotlin.jvm.internal.markers.KMappedMarker {
        private var index = 0
        override fun hasNext(): Boolean = index < size
        override fun next(): MatchGroup? {
            if (!hasNext()) throw NoSuchElementException()
            return get(index++)
        }
        fun remove() { throw UnsupportedOperationException("Operation is not supported for read-only collection") }
    }
    override fun get(index: Int): MatchGroup? {
        val start = __jvmMatcherStart(matcher, index)
        return if (start < 0) null else MatchGroup(__jvmMatcherGroup(matcher, index)!!, IntRange(start, __jvmMatcherEnd(matcher, index) - 1))
    }
    fun named(name: String): MatchGroup? {
        val start = __jvmMatcherStartNamed(matcher, name)
        return if (start < 0) null else MatchGroup(__jvmMatcherGroupNamed(matcher, name)!!, IntRange(start, __jvmMatcherEndNamed(matcher, name) - 1))
    }
}
private class MatcherResult(private val regex: Regex, private val input: CharSequence, private val matcher: Any): MatchResult {
    override val value: String get() = __jvmMatcherGroup(matcher, 0)!!
    override val range: IntRange get() = IntRange(__jvmMatcherStart(matcher, 0), __jvmMatcherEnd(matcher, 0) - 1)
    override val groups: MatchGroupCollection get() = MatcherGroups(matcher)
    override val groupValues: List<String> get() {
        val result = mutableListOf<String>()
        var index = 0
        while (index <= __jvmMatcherGroupCount(matcher)) { result.add(__jvmMatcherGroup(matcher, index) ?: ""); index++ }
        return result
    }
    override val destructured: MatchResult.Destructured get() = MatchResult.Destructured(this)
    override fun next(): MatchResult? {
        val end = __jvmMatcherEnd(matcher, 0)
        val nextIndex = if (end == __jvmMatcherStart(matcher, 0)) end + 1 else end
        return if (nextIndex > input.length) null else regex.find(input, nextIndex)
    }
}
fun namedGroup(groups: MatchGroupCollection, name: String): MatchGroup? = (groups as MatcherGroups).named(name)
