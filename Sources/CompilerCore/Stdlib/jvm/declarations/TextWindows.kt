package kotlin.text
fun CharSequence.windowed(size: Int, step: Int = 1, partialWindows: Boolean = false): List<String> = null!!
fun <R> CharSequence.windowed(size: Int, step: Int = 1, partialWindows: Boolean = false, transform: (CharSequence) -> R): List<R> = null!!
fun CharSequence.windowedSequence(size: Int, step: Int = 1, partialWindows: Boolean = false): kotlin.sequences.Sequence<String> = null!!
fun <R> CharSequence.windowedSequence(size: Int, step: Int = 1, partialWindows: Boolean = false, transform: (CharSequence) -> R): kotlin.sequences.Sequence<R> = null!!
fun CharSequence.chunked(size: Int): List<String> = null!!
fun <R> CharSequence.chunked(size: Int, transform: (CharSequence) -> R): List<R> = null!!
fun CharSequence.chunkedSequence(size: Int): kotlin.sequences.Sequence<String> = null!!
fun <R> CharSequence.chunkedSequence(size: Int, transform: (CharSequence) -> R): kotlin.sequences.Sequence<R> = null!!
