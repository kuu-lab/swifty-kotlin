interface J { fun f() = 1; fun g(): Int }

fun id(value: J): J = value
fun makeList() = listOf(object : J { override fun f() = 17; override fun g() = 18 })
val topLevel = listOf(object : J { override fun f() = 19; override fun g() = 20 })

fun main() {
    val l = listOf(object : J { override fun f() = 7; override fun g() = 8 })
    println(l[0].f())
    println(l[0].g())

    val argument = id(object : J { override fun f() = 9; override fun g() = 10 })
    println(argument.f())
    println(argument.g())

    val parenthesized = (object : J { override fun f() = 11; override fun g() = 12 })
    println(parenthesized.f())
    println(parenthesized.g())

    val nested = listOf(listOf(object : J { override fun f() = 13; override fun g() = 14; }))
    println(nested[0][0].f())
    println(nested[0][0].g())

    val direct = object : J { override fun f() = 15; override fun g() = 16 }
    println(direct.f())
    println(direct.g())
    println(makeList()[0].f())
    println(makeList()[0].g())
    println(topLevel[0].f())
    println(topLevel[0].g())

    println(listOf(object : J { override fun f() = 21; override fun g() = 22 })[0].f())
    println(object : J { override fun f() = 23; override fun g() = 24 }.g())
    println(run { 25; 26 })
    println(listOf(27).map { x -> x; x + 1 }[0])
    println(run({ 29; 30 }))
}
