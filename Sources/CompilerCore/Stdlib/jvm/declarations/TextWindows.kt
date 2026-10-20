package kotlin.text
fun CharSequence.windowed(size: Int, step: Int = 1, partialWindows: Boolean = false): List<String> = null!!
fun <R> CharSequence.windowed(size: Int, step: Int = 1, partialWindows: Boolean = false, transform: (CharSequence) -> R): List<R> = null!!
fun CharSequence.chunked(size: Int): List<String> = null!!
fun <R> CharSequence.chunked(size: Int, transform: (CharSequence) -> R): List<R> = null!!
