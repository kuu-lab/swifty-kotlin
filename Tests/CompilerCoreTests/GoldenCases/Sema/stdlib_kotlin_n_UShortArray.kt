package golden.sema

fun main() {
    val empty = UShortArray(0)
    val zeros = UShortArray(3)
    val storage = shortArrayOf(1, -1)
    val storageView = UShortArray(storage)
    val values = UShortArray(4) { (it + 1).toUShort() }
    println(empty.size)
    println(zeros[0])
    println(storageView.asShortArray()[1])
    println(values.toList())
}
