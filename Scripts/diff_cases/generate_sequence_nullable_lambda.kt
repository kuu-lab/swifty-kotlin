// KUU-1073: infer T = Int from a callback returning Int? with T : Any.
fun main() {
    val b = generateSequence { if (true) 1 else null }
    println(b.take(3).toList())
    var i = 0
    val c = generateSequence { i = i + 1; if (i <= 3) i else null }
    println(c.toList())
    println(generateSequence { 1 as Int? }.take(2).toList())
}
