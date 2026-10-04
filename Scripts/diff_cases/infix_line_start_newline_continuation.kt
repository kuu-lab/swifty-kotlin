infix fun Int.combine(other: Int): Int = this * 10 + other

// KUU-949: inside `(`/`[` a newline is not a statement separator, so an
// infix function name at the start of a continuation line still extends the
// expression (the upstream kotlinx.io `Segment.readInt` formatting).
fun readPacked(data: IntArray): Pair<Int, Int> {
    var pos = 0
    val i = (
            data[pos++] and 0xff shl 24
                    or (data[pos++] and 0xff shl 16)
                    or (data[pos++] and 0xff shl 8)
                    or (data[pos++] and 0xff)
            )
    return i to pos
}

fun main() {
    val data = intArrayOf(1, 2, 3, 4)
    val (i, pos) = readPacked(data)
    println("i=$i pos=$pos")

    var pos2 = 0
    val j = intArrayOf(
            data[pos2++]
                    or data[pos2++]
                    or data[pos2++]
    )[0]
    println("j=$j pos=$pos2")

    var pos3 = 0
    val c = (
            data[pos3++]
                    combine data[pos3++]
                    combine data[pos3++]
            )
    println("c=$c pos=$pos3")
}
