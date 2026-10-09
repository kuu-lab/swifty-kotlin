// KUU-1424: the outer parameter's expected type determines the nested constructor type argument.
interface Thing {
    fun name(): String
}

class Impl : Thing {
    override fun name(): String = "impl"
}

class Box<T>(val value: T)

fun makeThing(): Impl = Impl()

fun box(value: Box<Thing>): String = value.value.name()

fun main() {
    println(box(Box(makeThing())))
}
