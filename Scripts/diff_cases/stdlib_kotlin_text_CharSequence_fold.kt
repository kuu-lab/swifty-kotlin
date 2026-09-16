private class CountingSequence(private val value: String) : CharSequence {
    var lengthReads: Int = 0
    var getReads: Int = 0

    override val length: Int
        get() {
            lengthReads++
            return value.length
        }

    override fun get(index: Int): Char {
        getReads++
        return value[index]
    }

    override fun subSequence(startIndex: Int, endIndex: Int): CharSequence =
        value.substring(startIndex, endIndex)
}

private class MutableSequence(private val value: String) : CharSequence {
    var visibleLength: Int = value.length

    override val length: Int
        get() = visibleLength

    override fun get(index: Int): Char = value[index]

    override fun subSequence(startIndex: Int, endIndex: Int): CharSequence =
        value.substring(startIndex, endIndex)
}

private fun foldSum(source: CharSequence): Int =
    source.fold(0) { accumulator, value -> accumulator + value.code }

private fun foldIndexedTrace(source: CharSequence): String =
    source.foldIndexed("") { index, accumulator, value ->
        "$accumulator$index:$value;"
    }

private fun foldRightTrace(source: CharSequence): String =
    source.foldRight("") { value, accumulator -> "$accumulator$value;" }

private fun foldRightIndexedTrace(source: CharSequence): String =
    source.foldRightIndexed("") { index, value, accumulator ->
        "$accumulator$index:$value;"
    }

private fun directFoldReturn(source: CharSequence, target: Char): Int {
    source.fold(0) { accumulator, value ->
        if (value == target) return 41
        accumulator + 1
    }
    return -1
}

private fun safeFoldReturn(source: CharSequence?, target: Char): Int {
    source?.foldIndexed(0) { _, accumulator, value ->
        if (value == target) return 42
        accumulator + 1
    }
    return -1
}

private fun capturedFoldReturn(source: CharSequence, target: Char): Int {
    val expected = target
    source.foldRight(0, operation = { value, accumulator ->
        if (value == expected) return 43
        accumulator + 1
    })
    return -1
}

private fun namedFoldReturn(source: CharSequence, target: Char): Int {
    source.foldRightIndexed(initial = 0, operation = { index, value, accumulator ->
        if (index == 1 && value == target) return 44
        accumulator + 1
    })
    return -1
}

private fun throwingFold(source: CharSequence): String {
    return try {
        source.fold(0) { accumulator, value ->
            if (value == 'b') throw IllegalStateException("stop-fold")
            accumulator + value.code
        }
        "completed"
    } catch (error: IllegalStateException) {
        error.message ?: "null"
    }
}

fun main() {
    val utf16: CharSequence = "a\uD83D\uDE00b"
    println(foldSum(utf16))
    println(foldIndexedTrace(utf16))
    println(foldRightTrace(utf16))
    println(foldRightIndexedTrace(utf16))

    println(foldSum(""))
    println(foldIndexedTrace(""))
    println(foldRightTrace(""))
    println(foldRightIndexedTrace(""))

    val builder: CharSequence = StringBuilder("abc")
    println(foldSum(builder))
    println(foldIndexedTrace(builder))

    val tracked = CountingSequence("ab")
    println("${foldSum(tracked)}:${tracked.lengthReads}:${tracked.getReads}")

    val shrinking = MutableSequence("abcd")
    val dynamicFold = shrinking.fold("") { accumulator, value ->
        if (value == 'a') shrinking.visibleLength = 2
        accumulator + value
    }
    println(dynamicFold)

    val growing = StringBuilder("ab")
    val grownFold = (growing as CharSequence).fold("") { accumulator, value ->
        if (value == 'a') growing.append('c')
        accumulator + value
    }
    println(grownFold)

    println(directFoldReturn("abc", 'b'))
    println(directFoldReturn("abc", 'z'))
    println(safeFoldReturn("abc", 'b'))
    println(safeFoldReturn(null, 'b'))
    println(capturedFoldReturn("abc", 'c'))
    println(namedFoldReturn("abc", 'b'))
    println(throwingFold("abc"))
}
