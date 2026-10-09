import kotlin.sequences.first as seqFirst
import kotlin.sequences.firstOrNull as seqFirstOrNull
import kotlin.sequences.firstNotNullOf as seqFirstNotNullOf
import kotlin.sequences.firstNotNullOfOrNull as seqFirstNotNullOfOrNull

fun firstNotNullValue(values: Sequence<Int>): String =
    values.seqFirstNotNullOf { if (it > 1) "hit" else null }

fun firstNotNullValueOrNull(values: Sequence<Int>): String? =
    values.seqFirstNotNullOfOrNull { if (it > 1) "hit" else null }

fun terminal(kind: Int, values: Sequence<Int>): Int? = when (kind) {
    0 -> values.seqFirst()
    1 -> values.seqFirst(predicate = { true })
    2 -> values.seqFirstOrNull()
    3 -> values.seqFirstOrNull(predicate = { true })
    4 -> values.seqFirstNotNullOf(transform = { it })
    else -> values.seqFirstNotNullOfOrNull(transform = { it })
}

fun <T> nullableFirst(values: Sequence<T>): T = values.seqFirst()
fun <T> nullableFirstOrNull(values: Sequence<T>): T? = values.seqFirstOrNull { true }
fun <T, R : Any> transformed(values: Sequence<T>, transform: (T) -> R?): R =
    values.seqFirstNotNullOf(transform)

fun nonlocalFirst(): Int {
    sequenceOf(1).seqFirst { if (it > 0) return it; false }
    return -1
}
fun nonlocalFirstOrNull(): Int {
    sequenceOf(2).seqFirstOrNull { if (it > 0) return it; false }
    return -1
}
fun nonlocalNotNull(): Int {
    sequenceOf(3).seqFirstNotNullOf<Int, Int> { if (it > 0) return it; null }
    return -1
}
fun nonlocalNotNullOrNull(): Int {
    sequenceOf(4).seqFirstNotNullOfOrNull { if (it > 0) return it; null }
    return -1
}

class ThrowingFirstSequence : Sequence<Int> {
    override fun iterator(): Iterator<Int> = object : Iterator<Int> {
        override fun hasNext(): Boolean = throw IllegalArgumentException("iterator")
        override fun next(): Int = 0
    }
}

fun main() {
    val values = sequenceOf(1, 2, 3)
    println(firstNotNullValue(values))
    println(firstNotNullValueOrNull(values) ?: "missing")
    println(values.seqFirstNotNullOfOrNull { null } ?: "missing")
    try {
        values.seqFirstNotNullOf<Int, String> { null }
        println("unexpected")
    } catch (e: NoSuchElementException) {
        println(e.message)
    }

    for (kind in 0..5) {
        val suffix = sequenceOf(1, 2).map {
            if (it == 2) throw IllegalStateException("suffix")
            it
        }
        println(terminal(kind, suffix))
        val iterator = listOf(1, 2).iterator()
        println(terminal(kind, iterator.asSequence()))
        println(iterator.next())
        println(terminal(kind, generateSequence(1) { it }))
        println(terminal(kind, sequenceOf(7)))
        try {
            println(terminal(kind, emptySequence<Int>()))
        } catch (e: NoSuchElementException) {
            println(e.message)
        }
        try {
            terminal(kind, ThrowingFirstSequence())
        } catch (e: IllegalArgumentException) {
            println(e.message)
        }
    }

    println(nullableFirst(sequenceOf<String?>(null, "tail")))
    println(nullableFirstOrNull(sequenceOf<Int?>(null, 2)))
    println(sequenceOf<String?>(null, "tail").seqFirst { it != null })
    println(transformed(sequenceOf<String?>(null, "tail")) { it })
    println(sequenceOf<Int?>(null, 2, 3).seqFirstNotNullOfOrNull { it })
    println(sequenceOf<Int?>(null).seqFirstNotNullOfOrNull { it })
    println(sequenceOf(1, 2).seqFirstOrNull { false })
    try { sequenceOf(1).seqFirst { false } }
    catch (e: NoSuchElementException) { println(e.message) }

    println(nonlocalFirst())
    println(nonlocalFirstOrNull())
    println(nonlocalNotNull())
    println(nonlocalNotNullOrNull())

    val interleaved = sequenceOf(1, 2, 3).map { println("produce:$it"); it }
    println(interleaved.seqFirstNotNullOf {
        println("transform:$it")
        if (it == 2) "hit" else null
    })
    println(sequenceOf(1, 2, 3).map { println("up:$it"); it }.seqFirst {
        println("predicate:$it")
        it == 2
    })
    try { sequenceOf(1).seqFirst { throw IllegalStateException("predicate") } }
    catch (e: IllegalStateException) { println(e.message) }
    try { sequenceOf(1).seqFirstOrNull { throw IllegalStateException("nullable-predicate") } }
    catch (e: IllegalStateException) { println(e.message) }
    try { sequenceOf(1).seqFirstNotNullOf { throw IllegalStateException("transform") } }
    catch (e: IllegalStateException) { println(e.message) }
    try { sequenceOf(1).seqFirstNotNullOfOrNull { throw IllegalStateException("nullable-transform") } }
    catch (e: IllegalStateException) { println(e.message) }
    println(listOf(3).first())
    println(listOf(3).firstOrNull { true })
}
