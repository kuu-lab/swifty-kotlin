@Suppress("DEPRECATION")
fun main() {
    var calls = 0
    val one = listOf("x")
    println(one.maxBy { calls++; it.length })
    println("listMaxBy=$calls")
    calls = 0
    println(one.maxByOrNull { calls++; it.length })
    println("listMaxByOrNull=$calls")
    calls = 0
    println(one.minBy { calls++; it.length })
    println("listMinBy=$calls")
    calls = 0
    println(one.minByOrNull { calls++; it.length })
    println("listMinByOrNull=$calls")

    val iterableOne: Iterable<String> = listOf("x")
    calls = 0
    println(iterableOne.maxBy { calls++; it.length })
    println("iterableMaxBy=$calls")
    calls = 0
    println(iterableOne.maxByOrNull { calls++; it.length })
    println("iterableMaxByOrNull=$calls")
    calls = 0
    println(iterableOne.minBy { calls++; it.length })
    println("iterableMinBy=$calls")
    calls = 0
    println(iterableOne.minByOrNull { calls++; it.length })
    println("iterableMinByOrNull=$calls")

    val mapOne = mapOf(1 to "x")
    calls = 0
    println(mapOne.maxBy { calls++; it.value.length }.key)
    println("mapMaxBy=$calls")
    calls = 0
    println(mapOne.minBy { calls++; it.value.length }.key)
    println("mapMinBy=$calls")
    calls = 0
    println(mapOne.maxByOrNull { calls++; it.value.length }?.key)
    println("mapMaxByOrNull=$calls")
    calls = 0
    println(mapOne.minByOrNull { calls++; it.value.length }?.key)
    println("mapMinByOrNull=$calls")
}
