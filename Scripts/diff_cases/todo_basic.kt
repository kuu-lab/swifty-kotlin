fun compute(flag: Int): Int {
    if (flag > 0) return flag
    TODO("negative input")
}

fun main() {
    println(compute(3))
    try {
        compute(-1)
    } catch (e: NotImplementedError) {
        println("caught: " + e.message)
    }
    try {
        TODO()
    } catch (e: Error) {
        println("error: " + e.message)
    }
    try {
        TODO("later")
    } catch (e: Throwable) {
        println("throwable: " + e.message)
    }
}
