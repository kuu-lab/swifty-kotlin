@JvmInline
value class Counter(val raw: Long) {
    val amount: Long get() = raw
    fun amount(): Long = raw
}

fun inspect(value: Counter?, expected: Counter) {
    println(value?.raw)
    println(value?.amount)
    println(value?.amount())
    println(value?.amount ?: 42L)
    println(value == expected)
    println(expected == value)
    println(value != expected)
    println(expected != value)
    println(value == null)
}

fun nullable(value: Counter): Counter? = value

@JvmInline
value class Reading(val raw: Double)

fun inspectReading(value: Reading?, expected: Reading) {
    println(value?.raw)
    println(value == expected)
    println(expected == value)
    println(value == null)
}

class ScalarHolder(val raw: Long) {
    val amount: Long get() = raw
    fun amount(offset: Long = 0L): Long = raw + offset
    fun missing(): Long? = null
}

fun inspectHolder(value: ScalarHolder?) {
    println(value?.raw)
    println(value?.amount)
    println(value?.amount())
    println(value?.missing())
}

fun main() {
    val minimum = Counter(Long.MIN_VALUE)
    inspect(nullable(minimum), minimum)
    inspect(Counter(0L), Counter(0L))
    inspect(Counter(7L), Counter(7L))
    inspect(null, minimum)
    inspect(Counter(7L), minimum)
    var local: Counter? = minimum
    inspect(local, minimum)
    local = null
    inspect(local, minimum)
    val negativeZero = Reading(-0.0)
    inspectReading(negativeZero, negativeZero)
    inspectReading(negativeZero, Reading(0.0))
    inspectReading(Reading(Double.NaN), Reading(Double.NaN))
    inspectReading(null, negativeZero)
    inspectHolder(ScalarHolder(Long.MIN_VALUE))
    inspectHolder(null)
}
