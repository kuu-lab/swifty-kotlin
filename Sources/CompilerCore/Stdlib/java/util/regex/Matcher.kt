package java.util.regex

import kotlin.text.MatchResult
import kotlin.text.Regex

public class Matcher internal constructor(
    private val regex: Regex,
    input: String
) {
    private var input: String = input
    private var regionStart: Int = 0
    private var regionEnd: Int = input.length
    private var matches: Iterator<MatchResult> = makeMatchIterator()
    private var lastMatch: MatchResult? = null

    public fun reset(): Matcher = reset(input)

    public fun reset(input: CharSequence): Matcher {
        this.input = input.toString()
        regionStart = 0
        regionEnd = this.input.length
        resetMatches()
        return this
    }

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

    public fun find(): Boolean {
        lastMatch = null
        if (!matches.hasNext()) return false
        lastMatch = matches.next()
        return true
    }

    public fun start(): Int = regionStart + currentMatch().range.first

    public fun end(): Int = regionStart + currentMatch().range.last + 1

    public fun group(): String = currentMatch().value

    public fun group(group: Int): String? = currentMatch().groups[group]?.value

    public fun start(group: Int): Int {
        val range = currentMatch().groups[group]?.range ?: return -1
        return regionStart + range.first
    }

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
