// contentDeepEquals must be callable with infix syntax (KUU-1417).
fun main() {
    val a1: Array<Any?> = arrayOf(arrayOf(1, 2), arrayOf(3))
    val a2: Array<Any?> = arrayOf(arrayOf(1, 2), arrayOf(3))
    val a3: Array<Any?> = arrayOf(arrayOf(1, 2), arrayOf(4))
    val empty: Array<Any?> = arrayOf()

    println(a1 contentDeepEquals a2)
    println(a1 contentDeepEquals a3)
    println(a1 contentDeepEquals empty)
    println(a1.contentDeepEquals(a2))

    val primitiveNested = arrayOf(intArrayOf(1, 2), intArrayOf(3))
    val primitiveNestedSame = arrayOf(intArrayOf(1, 2), intArrayOf(3))
    println(primitiveNested contentDeepEquals primitiveNestedSame)

    val self: Array<Any?> = arrayOfNulls(1)
    self[0] = self
    println(self contentDeepEquals self)
}
