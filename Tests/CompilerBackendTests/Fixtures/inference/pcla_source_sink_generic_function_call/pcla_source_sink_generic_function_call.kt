fun box(): String {
    testYield()
    testMaterialize()
    return "OK"
}

fun testYield() {
    val arg: UserKlass = UserKlass()
    build {
        yield(id(arg))
    }
}

fun testMaterialize() {
    fun consume(arg: UserKlass) {}
    build {
        consume(id(materialize()))
    }
}

class Buildee<CT> {
    fun yield(arg: CT) {}
    fun materialize(): CT = UserKlass() as CT
}

fun <FT> build(instructions: Buildee<FT>.() -> Unit): Buildee<FT> =
    Buildee<FT>().apply(instructions)

class UserKlass

fun <T> id(arg: T): T = arg

fun main() {
    println(box())
}
