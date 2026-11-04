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
    return this.toString().splitIntoLines()
}

public fun String.lineSequence(): Sequence<String> {
    return normalizeLineSeparators().splitToSequence("\n")
}

public fun CharSequence.lineSequence(): Sequence<String> {
    return this.toString().normalizeLineSeparators().splitToSequence("\n")
}
