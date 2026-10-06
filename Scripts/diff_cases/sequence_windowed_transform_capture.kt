// KUU-1307: transforms escape into the window iterator's anonymous object.
fun windows(bonus: Int): Sequence<Int> =
    sequenceOf(1, 2, 3).windowed(2, 1, false) { it.size + bonus }

fun main() {
    println(sequenceOf(1, 2, 3).windowed(2, 1, false) { it.size }.toList())
    println(sequenceOf(1, 2, 3).windowed(2) { it.size }.toList())
    println(sequenceOf(1, 2, 3).windowed(2, 1, true) { it.size }.toList())
    println(sequenceOf(1, 2, 3, 4, 5).windowed(2, 3, true) { it.sum() }.toList())
    println(windows(10).toList())
    val label = "window"
    println(sequenceOf(1, 2, 3).windowed(2) { "$label:${it.size}" }.toList())
    println(emptySequence<Int>().windowed(2) { it.size }.toList())
    println(sequenceOf(1, 2, 3).windowed(2, 1, false).toList())
}
