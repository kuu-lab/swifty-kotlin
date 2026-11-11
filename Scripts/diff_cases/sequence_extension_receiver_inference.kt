import kotlin.sequences.SequenceScope

class Entry(val n: Int)

suspend fun SequenceScope<Int>.yieldI(x: Int) { yield(x) }
suspend fun SequenceScope<Entry>.collectEntry(entry: Entry) { yield(entry) }
fun readEntry(entry: Entry): Int = entry.n

fun main() {
    val ints = sequence { yieldI(2) }
    println(ints.first() + 1)

    val entries = sequence { collectEntry(Entry(7)) }
    println(entries.first().n)
    val cursor = entries.iterator()
    while (cursor.hasNext()) {
        println(readEntry(cursor.next()))
    }

    val explicitReceiver = sequence { this.collectEntry(Entry(9)) }
    println(readEntry(explicitReceiver.first()))
    val mixed = sequence { yield(Entry(10)); collectEntry(Entry(11)) }
    println(mixed.map { it.n }.toList())

    val iter = iterator { collectEntry(Entry(13)) }
    println(readEntry(iter.next()))
}
