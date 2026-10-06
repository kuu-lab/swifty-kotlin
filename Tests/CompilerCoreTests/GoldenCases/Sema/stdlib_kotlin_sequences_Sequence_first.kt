import kotlin.sequences.first as seqFirst
import kotlin.sequences.firstOrNull as seqFirstOrNull
import kotlin.sequences.firstNotNullOf as seqFirstNotNullOf
import kotlin.sequences.firstNotNullOfOrNull as seqFirstNotNullOfOrNull

fun <T> firstValue(values: Sequence<T>): T = values.seqFirst()
fun <T> firstMatch(values: Sequence<T>): T = values.seqFirst(predicate = { true })
fun <T> firstValueOrNull(values: Sequence<T>): T? = values.seqFirstOrNull()
fun <T> firstMatchOrNull(values: Sequence<T>): T? = values.seqFirstOrNull(predicate = { true })

fun firstNotNullValue(values: Sequence<Int>): String =
    values.seqFirstNotNullOf(transform = { if (it > 1) "hit" else null })

fun firstNotNullValueOrNull(values: Sequence<Int>): String? =
    values.seqFirstNotNullOfOrNull(transform = { if (it > 1) "hit" else null })
