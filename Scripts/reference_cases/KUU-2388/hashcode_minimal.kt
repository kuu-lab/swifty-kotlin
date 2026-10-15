fun box(): String {
    val h = java.util.Arrays.hashCode(intArrayOf(1, 2, 3))
    return if (h == 30817) "OK" else "FAIL:$h"
}

fun main() {
    print(box())
}
