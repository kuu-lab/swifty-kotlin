package java.util.regex

import kotlin.text.MatchResult
import kotlin.text.Regex

/** A stateful matcher backed by the bundled Kotlin regex implementation. */
public class Matcher internal constructor(
    private val regex: Regex,
    input: String
) {
    private var input: String = input
    private var regionStart: Int = 0
    private var regionEnd: Int = input.length
    private var matches: Iterator<MatchResult> = makeMatchIterator()
    private var lastMatch: MatchResult? = null

    /** Resets this matcher to its original input and full-input region. */
    public fun reset(): Matcher = reset(input)

    /** Resets this matcher to [input] and its full-input region. */
    public fun reset(input: CharSequence): Matcher {
        this.input = input.toString()
        regionStart = 0
        regionEnd = this.input.length
        resetMatches()
        return this
    }

    /** Restricts subsequent searches to the half-open range `[start, end)`. */
    public fun region(start: Int, end: Int): Matcher {
        if (start < 0 || end < 0 || start > input.length || end > input.length) {
            throw IndexOutOfBoundsException("Region [$start, $end) out of bounds for input length ${input.length}")
        }
        if (start > end) {
            throw IllegalArgumentException("Start index must not exceed end index")
        }
        regionStart = start
        regionEnd = end
        resetMatches()
        return this
    }

    /** Finds the next match within the current region. */
    public fun find(): Boolean {
        lastMatch = null
        if (!matches.hasNext()) return false
        lastMatch = matches.next()
        return true
    }

    /** Returns the start offset of the current match in the original input. */
    public fun start(): Int = regionStart + currentMatch().range.first

    /** Returns the exclusive end offset of the current match in the original input. */
    public fun end(): Int = regionStart + currentMatch().range.last + 1

    /** Returns the entire current match. */
    public fun group(): String = currentMatch().value

    /** Returns the requested capture group, or null when it did not participate. */
    public fun group(group: Int): String? = currentMatch().groups[group]?.value

    /** Returns the start offset of a capture group, or -1 when it did not participate. */
    public fun start(group: Int): Int {
        val range = currentMatch().groups[group]?.range ?: return -1
        return regionStart + range.first
    }

    /** Returns the exclusive end offset of a capture group, or -1 when it did not participate. */
    public fun end(group: Int): Int {
        val range = currentMatch().groups[group]?.range ?: return -1
        return regionStart + range.last + 1
    }

    private fun currentMatch(): MatchResult =
        lastMatch ?: throw IllegalStateException("No match available")

    private fun makeMatchIterator(): Iterator<MatchResult> =
        regex.findAll(input.substring(regionStart, regionEnd)).iterator()

    private fun resetMatches() {
        lastMatch = null
        matches = makeMatchIterator()
    }
}
