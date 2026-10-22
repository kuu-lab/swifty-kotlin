package kotlin.text

public inline fun CharSequence.trim(predicate: (Char) -> Boolean): CharSequence {
    var startIndex = 0
    var endIndex = length - 1
    var startFound = false
    while (startIndex <= endIndex) {
        val index = if (!startFound) startIndex else endIndex
        val match = predicate(this[index])
        if (!startFound) {
            if (!match) startFound = true else startIndex += 1
        } else {
            if (!match) break else endIndex -= 1
        }
    }
    return this.subSequence(startIndex, endIndex + 1)
}

public inline fun CharSequence.trimStart(predicate: (Char) -> Boolean): CharSequence {
    val endIndex = length
    var index = 0
    while (index < endIndex) {
        if (!predicate(this[index])) return this.subSequence(index, length)
        index += 1
    }
    return ""
}

public inline fun CharSequence.trimEnd(predicate: (Char) -> Boolean): CharSequence {
    var index = length - 1
    while (index >= 0) {
        if (!predicate(this[index])) return this.subSequence(0, index + 1)
        index -= 1
    }
    return ""
}

public fun CharSequence.trim(vararg chars: Char): CharSequence = trim { it in chars }
public fun CharSequence.trimStart(vararg chars: Char): CharSequence = trimStart { it in chars }
public fun CharSequence.trimEnd(vararg chars: Char): CharSequence = trimEnd { it in chars }

public fun String.trim(vararg chars: Char): String = trim { it in chars }
public fun String.trimStart(vararg chars: Char): String = trimStart { it in chars }
public fun String.trimEnd(vararg chars: Char): String = trimEnd { it in chars }

public fun CharSequence.trim(): CharSequence = trim { it.isWhitespace() }
public fun CharSequence.trimStart(): CharSequence = trimStart { it.isWhitespace() }
public fun CharSequence.trimEnd(): CharSequence = trimEnd { it.isWhitespace() }

public fun String.trim(): String {
    var start = 0
    var end = length
    while (start < end) {
        if (!this[start].isWhitespace()) break
        start++
    }
    while (end > start) {
        if (!this[end - 1].isWhitespace()) break
        end--
    }
    if (start == 0 && end == length) return this
    if (start == end) return ""
    return this.substring(start, end)
}

public inline fun String.trim(predicate: (Char) -> Boolean): String {
    var start = 0
    var end = length
    while (start < end) {
        if (!predicate(this[start])) break
        start++
    }
    while (end > start) {
        if (!predicate(this[end - 1])) break
        end--
    }
    if (start == 0 && end == length) return this
    if (start == end) return ""
    return this.substring(start, end)
}

public fun String.trimStart(): String {
    var i = 0
    while (i < length) {
        if (!this[i].isWhitespace()) break
        i++
    }
    if (i == 0) return this
    if (i == length) return ""
    return this.substring(i)
}

public inline fun String.trimStart(predicate: (Char) -> Boolean): String {
    var i = 0
    while (i < length) {
        if (!predicate(this[i])) break
        i++
    }
    if (i == 0) return this
    if (i == length) return ""
    return this.substring(i)
}

public fun String.trimEnd(): String {
    var i = length
    while (i > 0) {
        if (!this[i - 1].isWhitespace()) break
        i--
    }
    if (i == length) return this
    if (i == 0) return ""
    return this.substring(0, i)
}

public inline fun String.trimEnd(predicate: (Char) -> Boolean): String {
    var i = length
    while (i > 0) {
        if (!predicate(this[i - 1])) break
        i--
    }
    if (i == length) return this
    if (i == 0) return ""
    return this.substring(0, i)
}
