class CloneBox(var value: Int)

fun <T> duplicate(values: Array<T>): Array<T> = values.clone()

fun main() {
    val box = CloneBox(7)
    val original = arrayOf(box)
    val cloned: Array<CloneBox> = duplicate(original)
    cloned[0].value = 9
    println(original[0].value)
    cloned[0] = CloneBox(11)
    println(original[0].value)
    println(cloned[0].value)

    val ints = intArrayOf(1, 2, 3)
    val clonedInts: IntArray = ints.clone()
    clonedInts[0] = 99
    println(ints.toList())
    println(clonedInts.toList())

    val copied = ints.copyOf()
    copied[1] = 88
    println(ints.toList())
    println(copied.toList())
}
