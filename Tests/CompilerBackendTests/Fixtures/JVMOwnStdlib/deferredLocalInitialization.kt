import kotlin.coroutines.*

@JvmInline value class Counter(val value: Int)

fun branch(flag: Boolean): Long {
    val result: Long
    if (flag) { result = 4000000000L } else { result = 7L }
    return result
}
fun choice(value: Int): String {
    val result: String
    when (value) { 0 -> result = "zero"; else -> result = "other" }
    return result
}
fun loop(): Int {
    var result: Int
    while (true) { result = 5; break }
    return result
}
fun doLoop(): Int {
    var result: Int
    do { result = 6 } while (false)
    return result
}
fun exceptional(fail: Boolean): Int {
    var result: Int
    try {
        if (fail) throw IllegalStateException("expected")
        result = 8
    } catch (error: IllegalStateException) { result = 9 }
    return result
}
fun finalized(): Int {
    var result: Int
    while (true) {
        try { result = 10; break } finally { println("finally") }
    }
    return result
}
fun <T> identity(value: T): T { val result: T; result = value; return result }
suspend fun resumed(): Int = suspendCoroutine<Int> { continuation -> continuation.resume(11) }
suspend fun main() {
    var direct: Int; direct = 1; println(direct)
    val flag: Boolean; flag = true; println(flag)
    val byte: Byte; byte = 2; println(byte)
    val short: Short; short = 3; println(short)
    val char: Char; char = 'A'; println(char)
    val float: Float; float = 1.5f; println(float)
    val double: Double; double = 2.5; println(double)
    println(branch(true)); println(branch(false))
    println(choice(0)); println(choice(1)); println(loop()); println(doLoop())
    println(exceptional(false)); println(exceptional(true)); println(finalized())
    val nullable: String?; nullable = null; println(nullable)
    val array: IntArray; array = intArrayOf(12); println(array[0])
    val callable: (Int) -> Int; callable = { it + 1 }; println(callable(12))
    var shared: Int; shared = 13
    val increment = { shared += 1 }; increment(); println(shared)
    val captured: Int; captured = 15
    val reader = object { fun read(): Int = captured }; println(reader.read())
    val callbacks = mutableListOf<() -> Int>()
    for (index in 1..3) { var item: Int; item = index; callbacks.add { item } }
    println(callbacks.map { it() })
    val result: Int; result = resumed(); println(result)
    println(identity("generic"))
    val unit: Unit; unit = println("unit initializer"); println(unit)
    var mutableUnit: Unit; mutableUnit = Unit
    val unitReader = { mutableUnit }; println(unitReader())
    val unitObject = object { fun read(): Unit = unit }; println(unitObject.read())
    val mutableUnitObject = object { fun read(): Unit = mutableUnit }; println(mutableUnitObject.read())
    val unsigned: UInt; unsigned = 42u; println(unsigned)
    val nullableInt: Int?; nullableInt = 17; println(nullableInt)
    val counter: Counter; counter = Counter(18); println(counter.value)
}
