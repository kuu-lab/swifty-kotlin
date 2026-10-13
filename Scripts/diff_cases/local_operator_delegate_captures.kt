import kotlin.reflect.KProperty

class CaptureDelegate(var value: Int)
fun capturedOperators(seed: Int) {
    operator fun CaptureDelegate.provideDelegate(thisRef: Any?, property: KProperty<*>): CaptureDelegate = CaptureDelegate(seed)
    operator fun CaptureDelegate.getValue(thisRef: Any?, property: KProperty<*>): Int = value + seed
    operator fun CaptureDelegate.setValue(thisRef: Any?, property: KProperty<*>, newValue: Int) { value = newValue - seed }
    var answer by CaptureDelegate(0)
    println(answer)
    answer = 50
    println(answer)
    answer += 2
    println(answer)
    val read = { answer }
    fun readLocal(): Int = answer
    println(read())
    println(readLocal())
    val create = { val nested by CaptureDelegate(0); nested }
    fun createLocal(): Int {
        val nested by CaptureDelegate(0)
        return nested
    }
    println(create())
    println(createLocal())
}

class CountingDelegate
fun mutableCapture() {
    var count = 0
    operator fun CountingDelegate.getValue(thisRef: Any?, property: KProperty<*>): Int {
        count += 1
        return count
    }
    val answer by CountingDelegate()
    println(answer)
    println(answer)
    println(count)
}

fun main() {
    capturedOperators(20)
    mutableCapture()
}
