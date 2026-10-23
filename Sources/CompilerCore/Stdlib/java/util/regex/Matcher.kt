package java.util.regex

import kotlin.text.MatchResult
import kotlin.text.Regex
import kotlin.text.escapeReplacement
import kotlin.text.groupNames

public class Matcher internal constructor(
    private val pattern: Pattern,
    input: String
) {
    private val regex: Regex
        get() = pattern.regex

    private var input: String = input
    private var regionStart: Int = 0
    private var regionEnd: Int = input.length
    private var matchIterator: Iterator<MatchResult> = makeMatchIterator()
    private var lastMatch: MatchResult? = null
    private var appendPosition: Int = 0

    public fun pattern(): Pattern = pattern

    public fun reset(): Matcher = reset(input)

    public fun reset(input: CharSequence): Matcher {
        this.input = input.toString()
        regionStart = 0
        regionEnd = this.input.length
        appendPosition = 0
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

    public fun regionStart(): Int = regionStart

    public fun regionEnd(): Int = regionEnd

    public fun matches(): Boolean {
        lastMatch = regex.matchEntire(input.substring(regionStart, regionEnd))
        return lastMatch != null
    }

    public fun lookingAt(): Boolean {
        lastMatch = regex.matchAt(input.substring(regionStart, regionEnd), 0)
        return lastMatch != null
    }

    public fun find(): Boolean {
        lastMatch = null
        if (!matchIterator.hasNext()) return false
        lastMatch = matchIterator.next()
        return true
    }

    public fun find(start: Int): Boolean {
        if (start < 0 || start > input.length) {
            throw IndexOutOfBoundsException("Start index $start out of bounds for input length ${input.length}")
        }
        regionStart = 0
        regionEnd = input.length
        appendPosition = 0
        lastMatch = null
        matchIterator = regex.findAll(input, start).iterator()
        return find()
    }

    public fun start(): Int = regionStart + currentMatch().range.first

    public fun end(): Int = regionStart + currentMatch().range.last + 1

    public fun group(): String = currentMatch().value

    public fun group(group: Int): String? = currentMatch().groups[group]?.value

    public fun group(name: String): String? = currentMatch().groups[name]?.value

    public fun start(group: Int): Int {
        val range = currentMatch().groups[group]?.range ?: return -1
        return regionStart + range.first
    }

    public fun end(group: Int): Int {
        val range = currentMatch().groups[group]?.range ?: return -1
        return regionStart + range.last + 1
    }

    public fun start(name: String): Int {
        val range = currentMatch().groups[name]?.range ?: return -1
        return regionStart + range.first
    }

    public fun end(name: String): Int {
        val range = currentMatch().groups[name]?.range ?: return -1
        return regionStart + range.last + 1
    }

    public fun replaceAll(replacement: String): String = replace(replacement, replaceFirst = false)

    public fun replaceFirst(replacement: String): String = replace(replacement, replaceFirst = true)

    public fun appendReplacement(buffer: StringBuilder, replacement: String): Matcher {
        val match = currentMatch()
        val matchStart = regionStart + match.range.first
        val matchEnd = regionStart + match.range.last + 1
        if (matchStart < appendPosition) {
            throw IllegalStateException("Match start precedes the current append position")
        }
        buffer.append(input.substring(appendPosition, matchStart))
        appendReplacementText(buffer, replacement, match)
        appendPosition = matchEnd
        return this
    }

    public fun appendTail(buffer: StringBuilder): StringBuilder {
        if (appendPosition < input.length) {
            buffer.append(input.substring(appendPosition))
        }
        appendPosition = input.length
        return buffer
    }

    private fun replace(replacement: String, replaceFirst: Boolean): String {
        val regionText = input.substring(regionStart, regionEnd)
        val replaced = if (replaceFirst) {
            regex.replaceFirst(regionText, replacement)
        } else {
            regex.replace(regionText, replacement)
        }
        lastMatch = null
        resetMatches()
        return input.substring(0, regionStart) + replaced + input.substring(regionEnd)
    }

    private fun appendReplacementText(buffer: StringBuilder, replacement: String, match: MatchResult) {
        var index = 0
        val groupCount = match.groups.size - 1
        while (index < replacement.length) {
            when (val character = replacement[index]) {
                '\\' -> {
                    if (index + 1 >= replacement.length) {
                        throw IllegalArgumentException("Character to be escaped is missing")
                    }
                    buffer.append(replacement[index + 1])
                    index += 2
                }
                '$' -> {
                    if (index + 1 >= replacement.length) {
                        throw IllegalArgumentException("Illegal group reference: group index is missing")
                    }
                    if (replacement[index + 1] == '{') {
                        val nameStart = index + 2
                        var closing = nameStart
                        while (closing < replacement.length && replacement[closing] != '}') closing++
                        if (closing == replacement.length) {
                            throw IllegalArgumentException("Named capturing group is missing trailing '}'")
                        }
                        val name = replacement.substring(nameStart, closing)
                        if (name.isEmpty() || !regex.groupNames.contains(name)) {
                            throw IllegalArgumentException("No group with name {$name}")
                        }
                        buffer.append(match.groups[name]?.value ?: "")
                        index = closing + 1
                    } else {
                        val firstDigit = replacement[index + 1]
                        if (firstDigit < '0' || firstDigit > '9') {
                            throw IllegalArgumentException("Illegal group reference")
                        }
                        var group = firstDigit.code - '0'.code
                        if (group > groupCount) {
                            throw IllegalArgumentException("No group $group")
                        }
                        var cursor = index + 2
                        while (cursor < replacement.length) {
                            val digit = replacement[cursor]
                            if (digit < '0' || digit > '9') break
                            val nextGroup = group * 10 + digit.code - '0'.code
                            if (nextGroup > groupCount) break
                            group = nextGroup
                            cursor++
                        }
                        buffer.append(match.groups[group]?.value ?: "")
                        index = cursor
                    }
                }
                else -> {
                    buffer.append(character)
                    index++
                }
            }
        }
    }

    private fun currentMatch(): MatchResult =
        lastMatch ?: throw IllegalStateException("No match available")

    private fun makeMatchIterator(): Iterator<MatchResult> =
        regex.findAll(input.substring(regionStart, regionEnd)).iterator()

    private fun resetMatches() {
        lastMatch = null
        matchIterator = makeMatchIterator()
    }

    public companion object {
        public fun quoteReplacement(s: String): String = Regex.escapeReplacement(s)
    }
}
