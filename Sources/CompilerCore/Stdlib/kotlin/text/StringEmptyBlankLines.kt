package kotlin.text

import kotlin.contracts.ExperimentalContracts
import kotlin.contracts.contract

public fun CharSequence.isEmpty(): Boolean = this.length == 0

public fun CharSequence.isNotEmpty(): Boolean = this.length != 0

public fun CharSequence.isBlank(): Boolean {
    var i = 0
    while (i < this.length) {
        if (!this[i].isWhitespace()) return false
        i++
    }
    return true
}

public fun CharSequence.isNotBlank(): Boolean = !this.isBlank()

public inline fun <C, R> C.ifEmpty(defaultValue: () -> R): R where C : CharSequence, C : R {
    val value: CharSequence = this
    return if (value.isEmpty()) defaultValue() else this
}

public inline fun <C, R> C.ifBlank(defaultValue: () -> R): R where C : CharSequence, C : R {
    val value: CharSequence = this
    return if (value.isBlank()) defaultValue() else this
}

@OptIn(ExperimentalContracts::class)
public fun CharSequence?.isNullOrEmpty(): Boolean {
    contract {
        returns(false) implies (this@isNullOrEmpty != null)
    }
    val value = this
    if (value == null) return true
    return value!!.isEmpty()
}

@OptIn(ExperimentalContracts::class)
public fun CharSequence?.isNullOrBlank(): Boolean {
    contract {
        returns(false) implies (this@isNullOrBlank != null)
    }
    val value = this
    if (value == null) return true
    return value!!.isBlank()
}

public fun String?.orEmpty(): String {
    return this ?: ""
}

public fun String.lines(): List<String> {
    return splitIntoLines()
}

public fun CharSequence.lines(): List<String> {
    return lineSequence().toList()
}

public fun String.lineSequence(): Sequence<String> {
    return normalizeLineSeparators().splitToSequence("\n")
}

public fun CharSequence.lineSequence(): Sequence<String> {
    return LinesSequence(this)
}

// Mirrors kotlin-stdlib's LinesIterator: lines are delimited by CRLF, LF or CR,
// iteration reads through CharSequence.get, and a trailing separator yields an
// extra empty line. Building lines via subSequence/toString (instead of the
// receiver's toString()) keeps custom CharSequence implementations observable.
// A concrete Sequence class is used instead of `Sequence { ... }`: capturing the
// receiver in that lambda miscompiles when this file is built into the stdlib
// artifact.
private class LinesSequence(private val string: CharSequence) : Sequence<String> {
    override fun iterator(): Iterator<String> = LinesIterator(string)
}

private class LinesIterator(private val string: CharSequence) : Iterator<String> {
    private var state = 0
    private var tokenStartIndex = 0
    private var delimiterStartIndex = 0
    private var delimiterLength = 0

    override fun hasNext(): Boolean {
        if (state != 0) {
            return state == 1
        }
        if (delimiterLength < 0) {
            state = 2
            return false
        }
        var nextDelimiterLength = -1
        var nextDelimiterStartIndex = string.length
        var index = tokenStartIndex
        while (index < string.length) {
            val character = string[index]
            if (character == '\n' || character == '\r') {
                nextDelimiterLength = if (character == '\r' && index + 1 < string.length && string[index + 1] == '\n') 2 else 1
                nextDelimiterStartIndex = index
                break
            }
            index++
        }
        state = 1
        delimiterLength = nextDelimiterLength
        delimiterStartIndex = nextDelimiterStartIndex
        return true
    }

    override fun next(): String {
        if (!hasNext()) {
            throw NoSuchElementException()
        }
        state = 0
        val lastIndex = delimiterStartIndex
        val firstIndex = tokenStartIndex
        tokenStartIndex = delimiterStartIndex + delimiterLength
        return string.substring(firstIndex, lastIndex)
    }
}
