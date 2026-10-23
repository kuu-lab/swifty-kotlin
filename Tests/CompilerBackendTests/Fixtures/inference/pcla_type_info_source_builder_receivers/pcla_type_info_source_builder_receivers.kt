fun box(): String {
    testYield()
    return "OK"
}

fun testYield() {
    build {
        it.yield(this)
    }
}

class Buildee<CT> {
    fun yield(arg: CT) {}
}

fun <FT> build(instructions: UserKlass.(Buildee<FT>) -> Unit): Buildee<FT> =
    Buildee<FT>().apply { UserKlass().instructions(this) }

class UserKlass

fun main() {
    println(box())
}
