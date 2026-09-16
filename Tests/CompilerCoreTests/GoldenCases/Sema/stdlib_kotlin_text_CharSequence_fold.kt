package golden.sema

fun charSequenceFold(source: CharSequence, initial: Int): Int =
    source.fold(initial) { accumulator, value -> accumulator + value.code }

fun charSequenceFoldIndexed(source: CharSequence, initial: String): String =
    source.foldIndexed(initial = initial, operation = { index, accumulator, value ->
        "$accumulator$index:$value;"
    })

fun charSequenceFoldRight(source: CharSequence, initial: String): String =
    source.foldRight(initial) { value, accumulator -> "$accumulator$value;" }

fun charSequenceFoldRightIndexed(source: CharSequence, initial: String): String =
    source.foldRightIndexed(initial) { index, value, accumulator ->
        "$accumulator$index:$value;"
    }

fun directNonLocalFold(source: CharSequence, target: Char): Int {
    source.fold(0) { accumulator, value ->
        if (value == target) return accumulator + 1
        accumulator + 1
    }
    return -1
}

fun safeNonLocalFold(source: CharSequence?, target: Char): Int {
    source?.foldIndexed(0) { _, accumulator, value ->
        if (value == target) return accumulator + 1
        accumulator + 1
    }
    return -1
}
