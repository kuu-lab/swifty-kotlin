package kotlin.text
enum class RegexOption { IGNORE_CASE, MULTILINE, LITERAL, UNIX_LINES, COMMENTS, DOT_MATCHES_ALL, CANON_EQ }
class Regex {
    constructor(pattern: String)
    constructor(pattern: String, option: RegexOption)
    constructor(pattern: String, options: Set<RegexOption>)
    val pattern: String get() = null!!
    val options: Set<RegexOption> get() = null!!
    infix fun matches(input: CharSequence): Boolean = false
    fun containsMatchIn(input: CharSequence): Boolean = false
    fun find(input: CharSequence, startIndex: Int = 0): MatchResult? = null
    fun findAll(input: CharSequence, startIndex: Int = 0): kotlin.sequences.Sequence<MatchResult> = null!!
    fun matchEntire(input: CharSequence): MatchResult? = null
    fun matchAt(input: CharSequence, index: Int): MatchResult? = null
    fun matchesAt(input: CharSequence, index: Int): Boolean = false
    fun replace(input: CharSequence, replacement: String): String = null!!
    fun replace(input: CharSequence, transform: (MatchResult) -> CharSequence): String = null!!
    fun replaceFirst(input: CharSequence, replacement: String): String = null!!
    fun split(input: CharSequence, limit: Int = 0): List<String> = null!!
    fun splitToSequence(input: CharSequence, limit: Int = 0): kotlin.sequences.Sequence<String> = null!!
    override fun toString(): String = null!!
    companion object {
        fun fromLiteral(literal: String): Regex = null!!
        fun escape(literal: String): String = null!!
        fun escapeReplacement(literal: String): String = null!!
    }
}
interface MatchResult {
    val value: String
    val range: kotlin.ranges.IntRange
    val groups: MatchGroupCollection
    val groupValues: List<String>
    val destructured: Destructured
    class Destructured {
        constructor(match: MatchResult)
        operator fun component1(): String = null!!
        operator fun component2(): String = null!!
        operator fun component3(): String = null!!
        operator fun component4(): String = null!!
        operator fun component5(): String = null!!
        operator fun component6(): String = null!!
        operator fun component7(): String = null!!
        operator fun component8(): String = null!!
        operator fun component9(): String = null!!
        operator fun component10(): String = null!!
        fun toList(): List<String> = null!!
    }

    fun next(): MatchResult?
}
class MatchGroup {
    constructor(value: String, range: kotlin.ranges.IntRange)
    val value: String get() = null!!
    val range: kotlin.ranges.IntRange get() = null!!
    operator fun component1(): String = null!!
    operator fun component2(): kotlin.ranges.IntRange = null!!
}
interface MatchGroupCollection: Collection<MatchGroup?> {
    override val size: Int
    override fun isEmpty(): Boolean
    operator fun get(index: Int): MatchGroup?
}
operator fun MatchGroupCollection.get(name: String): MatchGroup? = null!!
fun String.toRegex(): Regex = null!!
fun String.toRegex(option: RegexOption): Regex = null!!
fun String.toRegex(options: Set<RegexOption>): Regex = null!!
infix fun CharSequence.matches(regex: Regex): Boolean = false
operator fun CharSequence.contains(regex: Regex): Boolean = false
fun CharSequence.replace(regex: Regex, replacement: String): String = null!!
fun CharSequence.replace(regex: Regex, transform: (MatchResult) -> CharSequence): String = null!!
fun CharSequence.replaceFirst(regex: Regex, replacement: String): String = null!!
fun CharSequence.split(regex: Regex, limit: Int = 0): List<String> = null!!
fun CharSequence.splitToSequence(regex: Regex, limit: Int = 0): kotlin.sequences.Sequence<String> = null!!