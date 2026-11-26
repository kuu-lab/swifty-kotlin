@file:kotlin.jvm.JvmName("StringsKt")
package kotlin.text

private fun checkTextWindowSizeStep(size: Int, step: Int) {
    if (size <= 0 || step <= 0) {
        val message = if (size != step) {
            "Both size $size and step $step must be greater than zero."
        } else {
            "size $size must be greater than zero."
        }
        throw IllegalArgumentException(message)
    }
}

fun CharSequence.windowed(size: Int, step: Int = 1, partialWindows: Boolean = false): List<String> = windowed(size, step, partialWindows) { it.toString() }
fun <R> CharSequence.windowed(size: Int, step: Int = 1, partialWindows: Boolean = false, transform: (CharSequence) -> R): List<R> {
    checkTextWindowSizeStep(size, step)
    val result = mutableListOf<R>()
    val inputLength = this.length
    var start = 0
    while (start < inputLength) {
        val remaining = inputLength - start
        if (remaining < size && !partialWindows) break
        val end = start + if (remaining < size) remaining else size
        result.add(transform(this.subSequence(start, end)))
        if (step > inputLength - start) break
        start += step
    }
    return result
}

fun CharSequence.windowedSequence(size: Int, step: Int = 1, partialWindows: Boolean = false): kotlin.sequences.Sequence<String> =
    windowedSequence(size, step, partialWindows) { it.toString() }

fun <R> CharSequence.windowedSequence(size: Int, step: Int = 1, partialWindows: Boolean = false, transform: (CharSequence) -> R): kotlin.sequences.Sequence<R> {
    checkTextWindowSizeStep(size, step)
    val source = this
    val inputLength = source.length
    return object : kotlin.sequences.Sequence<R> {
        override fun iterator(): Iterator<R> = object : Iterator<R> {
            var start = 0

            private fun hasWindow(): Boolean {
                if (start >= inputLength) return false
                return partialWindows || inputLength - start >= size
            }

            override fun hasNext(): Boolean = hasWindow()

            override fun next(): R {
                if (!hasWindow()) throw NoSuchElementException()
                val remaining = inputLength - start
                val end = start + if (remaining < size) remaining else size
                val result = transform(source.subSequence(start, end))
                start = if (step > remaining) inputLength else start + step
                return result
            }
        }
    }
}

fun CharSequence.chunked(size: Int): List<String> = windowed(size, size, true)
fun <R> CharSequence.chunked(size: Int, transform: (CharSequence) -> R): List<R> = windowed(size, size, true, transform)
fun CharSequence.chunkedSequence(size: Int): kotlin.sequences.Sequence<String> =
    windowedSequence(size, size, true)

fun <R> CharSequence.chunkedSequence(size: Int, transform: (CharSequence) -> R): kotlin.sequences.Sequence<R> =
    windowedSequence(size, size, true, transform)
