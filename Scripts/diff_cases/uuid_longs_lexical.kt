// NOTE: Uuid.LEXICAL_ORDER cannot be diffed here — JVM kotlinc compiles it as a
// deprecation ERROR (use naturalOrder), while kswiftc still accepts it with a
// warning. naturalOrder<Uuid>() exercises the same Comparator path.
@file:OptIn(kotlin.uuid.ExperimentalUuidApi::class)

import kotlin.uuid.Uuid
import kotlin.comparisons.naturalOrder

fun main() {
    val uuidStr = "550e8400-e29b-41d4-a716-446655440000"
    val uuid = Uuid.parse(uuidStr)

    uuid.toLongs { msb, lsb ->
        println("msb: ${msb == 0x550e8400e29b41d4L}")
        println("lsb: ${lsb == 0xa716446655440000uL.toLong()}")
    }

    val low = Uuid.parse("00000000-0000-0000-0000-000000000001")
    val high = Uuid.parse("00000000-0000-0000-0000-000000000002")
    println("natural compare: ${naturalOrder<Uuid>().compare(low, high) < 0}")
    val sorted = listOf(high, low).sortedWith(naturalOrder<Uuid>())
    println("sorted first is low: ${sorted[0] == low}")
    println("OK")
}
