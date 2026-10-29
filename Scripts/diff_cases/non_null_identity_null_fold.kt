private class Box
private var calls = 0
private fun create(): Box { calls++; return Box() }

fun main() {
    println(create() !== null)
    println(null !== create())
    println(create() === null)
    println(null === create())
    println(calls)
    val present: Box? = Box()
    val absent: Box? = null
    println(present !== null)
    println(present === null)
    println(absent !== null)
    println(absent === null)
    println(create() != null)
    println(create() == null)
    println(calls)
}
