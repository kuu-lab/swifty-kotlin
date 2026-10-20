// Uuid.generateV7() monotonicity under concurrent calls (KUU-2690): the
// packed (timestamp << 16 | version | counter) state must be updated through
// a CAS loop, so callers on parallel threads never observe duplicate or
// out-of-order uuids.
@file:OptIn(kotlin.uuid.ExperimentalUuidApi::class)

import kotlin.uuid.Uuid
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.runBlocking

fun main() {
    // Warm up the generator singleton on the main thread before fanning out.
    Uuid.generateV7()

    // Sequential calls are strictly increasing; calls landing in the same
    // millisecond are ordered by the counter field.
    var prev = Uuid.generateV7()
    var sequentialIncreasing = true
    val seenMsbs = HashSet<Long>()
    seenMsbs.add(prev.toLongs { msb, _ -> msb })
    repeat(2000) {
        val next = Uuid.generateV7()
        if (next <= prev) sequentialIncreasing = false
        seenMsbs.add(next.toLongs { msb, _ -> msb })
        prev = next
    }
    println("sequential strictly increasing: $sequentialIncreasing")
    println("sequential msbs distinct: ${seenMsbs.size == 2001}")

    // Fan out onto real dispatcher threads and collect every generated msb.
    val workerCount = 8
    val perWorker = 500
    val results = runBlocking {
        (1..workerCount).map {
            async(Dispatchers.Default) {
                var monotonic = true
                var p = Uuid.generateV7()
                val msbs = ArrayList<Long>(perWorker)
                msbs.add(p.toLongs { msb, _ -> msb })
                repeat(perWorker - 1) {
                    val n = Uuid.generateV7()
                    if (n <= p) monotonic = false
                    msbs.add(n.toLongs { msb, _ -> msb })
                    p = n
                }
                Pair(msbs, monotonic)
            }
        }.awaitAll()
    }
    val allMsbs = results.flatMap { it.first }
    println("concurrent total: ${allMsbs.size}")
    println("concurrent msbs distinct: ${allMsbs.toSet().size == allMsbs.size}")
    println("per-worker increasing: ${results.all { it.second }}")

    val bytes = prev.toByteArray()
    println("version=7: ${((bytes[6].toInt() and 0xFF) ushr 4) == 7}")
    println("variant=2: ${((bytes[8].toInt() and 0xFF) ushr 6) == 2}")
}
