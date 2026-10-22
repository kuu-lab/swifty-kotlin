@file:kotlin.jvm.JvmName("StringsKt")
package kotlin.text
fun CharSequence.windowed(size: Int, step: Int = 1, partialWindows: Boolean = false): List<String> = windowed(size, step, partialWindows) { it.toString() }
fun <R> CharSequence.windowed(size: Int, step: Int = 1, partialWindows: Boolean = false, transform: (CharSequence) -> R): List<R> {
    if (size <= 0 || step <= 0) {
        val message = if (size != step) {
            "Both size $size and step $step must be greater than zero."
        } else {
            "size $size must be greater than zero."
        }
        throw IllegalArgumentException(message)
    }
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
fun CharSequence.chunked(size: Int): List<String> = windowed(size, size, true)
fun <R> CharSequence.chunked(size: Int, transform: (CharSequence) -> R): List<R> = windowed(size, size, true, transform)
