package kotlin.text

// MIGRATION-TEXT-001: String 変換・切り出し関数
// 移行元: Sources/Runtime/RuntimeStringStdlib.swift

fun String.trim(): String {
    var startIndex = 0
    var endIndex = length - 1
    while (startIndex <= endIndex && this[startIndex].isWhitespace()) startIndex++
    while (endIndex >= startIndex && this[endIndex].isWhitespace()) endIndex--
    return if (startIndex > endIndex) "" else substring(startIndex, endIndex + 1)
}

fun String.trim(predicate: (Char) -> Boolean): String {
    var startIndex = 0
    var endIndex = length - 1
    while (startIndex <= endIndex && predicate(this[startIndex])) startIndex++
    while (endIndex >= startIndex && predicate(this[endIndex])) endIndex--
    return if (startIndex > endIndex) "" else substring(startIndex, endIndex + 1)
}

fun String.trimStart(): String = dropWhile { it.isWhitespace() }

fun String.trimStart(predicate: (Char) -> Boolean): String = dropWhile(predicate)

fun String.trimEnd(): String {
    var endIndex = length
    while (endIndex > 0 && this[endIndex - 1].isWhitespace()) endIndex--
    return if (endIndex == 0) "" else substring(0, endIndex)
}

fun String.trimEnd(predicate: (Char) -> Boolean): String {
    var endIndex = length
    while (endIndex > 0 && predicate(this[endIndex - 1])) endIndex--
    return if (endIndex == 0) "" else substring(0, endIndex)
}

fun String.take(n: Int): String {
    require(n >= 0)
    return substring(0, n.coerceAtMost(length))
}

fun String.takeLast(n: Int): String {
    require(n >= 0)
    val len = length
    return substring(len - n.coerceAtMost(len))
}

fun String.drop(n: Int): String {
    require(n >= 0)
    return substring(n.coerceAtMost(length))
}

fun String.dropLast(n: Int): String {
    require(n >= 0)
    return substring(0, (length - n).coerceAtLeast(0))
}

fun String.subSequence(startIndex: Int, endIndex: Int): String = substring(startIndex, endIndex)
