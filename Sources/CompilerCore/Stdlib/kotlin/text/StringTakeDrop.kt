package kotlin.text

public fun String.take(n: Int): String {
    require(n >= 0) { "Requested character count $n is less than zero." }
    val chars = this.toString().toList()
    if (n >= chars.size) return this
    return this.substring(0, n)
}

public fun String.takeLast(n: Int): String {
    require(n >= 0) { "Requested character count $n is less than zero." }
    val chars = this.toString().toList()
    val count = chars.size
    if (n >= count) return this
    return this.substring(count - n)
}

public fun String.drop(n: Int): String {
    require(n >= 0) { "Requested character count $n is less than zero." }
    val chars = this.toString().toList()
    if (n >= chars.size) return ""
    return this.substring(n)
}

public fun String.dropLast(n: Int): String {
    require(n >= 0) { "Requested character count $n is less than zero." }
    val chars = this.toString().toList()
    val count = chars.size
    if (n >= count) return ""
    return this.substring(0, count - n)
}

public fun String.takeWhile(predicate: (Char) -> Boolean): String {
    val chars = this.toString().toList()
    var index = 0
    while (index < chars.size) {
        if (!predicate(chars[index])) return this.substring(0, index)
        index++
    }
    return this
}

public fun String.takeLastWhile(predicate: (Char) -> Boolean): String {
    val chars = this.toString().toList()
    var index = chars.size - 1
    while (index >= 0) {
        if (!predicate(chars[index])) return this.substring(index + 1)
        index--
    }
    return this
}

public fun String.dropWhile(predicate: (Char) -> Boolean): String {
    val chars = this.toString().toList()
    var index = 0
    while (index < chars.size) {
        if (!predicate(chars[index])) return this.substring(index)
        index++
    }
    return ""
}
