fun box(): String {
    testYield()
    return "OK"
}

fun testYield() {
    build {
        yield(it)
    }
}

class Buildee<CT> {
    fun yield(arg: CT) {}
}

fun <FT> build(instructions: Buildee<FT>.(UserKlass) -> Unit): Buildee<FT> =
    Buildee<FT>().apply { this.instructions(UserKlass()) }

class UserKlass

fun main() {
    println(box())
}
