class UserKlass

class Buildee<T> {
    var variable: T = UserKlass() as T
}

fun <T> build(instructions: Buildee<T>.() -> Unit): Buildee<T> =
    Buildee<T>().apply(instructions)

fun box(): String {
    val arg: UserKlass = UserKlass()
    build { variable = arg }
    return "OK"
}

fun main() {
    print(box())
}
