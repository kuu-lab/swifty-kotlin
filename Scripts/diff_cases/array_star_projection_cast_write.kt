fun assign(a: Array<*>) {
    val b = a as Array<Any?>
    b[0] = 42
}

fun main() {
    val arr: Array<Int> = arrayOf(1, 2, 3)
    assign(arr)
    println(arr[0])
}
