// KUU-2211: Map.computeIfAbsent is callable on MutableMap delegate types and
// follows the Java Map null and existing-value behavior.

class MyMap : MutableMap<Int, String> by hashMapOf()

fun box(): String {
    val map = MyMap()
    return map.computeIfAbsent(42) { "OK" }
}

fun main() {
    val delegated = MyMap()
    println(box())
    println(delegated.computeIfAbsent(42) { "OK" })
    println(delegated.computeIfAbsent(42) { "wrong" })

    val values = linkedMapOf<Int, String?>(1 to "present", 2 to null)
    var calls = 0
    println(values.computeIfAbsent(1) { calls++; "wrong" })
    println(values.computeIfAbsent(2) { calls++; "filled" })
    println(values.computeIfAbsent(3) { calls++; null })
    println(values.containsKey(3))
    println("calls=$calls values=${values.entries.joinToString(",") { "${it.key}=${it.value}" }}")

    val getOrPutControl = mutableMapOf<Int, String>()
    println(getOrPutControl.getOrPut(5) { "control" })
    println(getOrPutControl.getOrPut(5) { "wrong" })
}
