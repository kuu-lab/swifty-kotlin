fun add(a: Int, b: Int): Int = a + b
fun identity(value: Any?): Any? = value
fun returnedLambda(): (Int) -> Int = { it * 2 }
fun returnedReference(): (Int, Int) -> Int = ::add
fun String.appendNumber(n: Int): String = this + n

class Adder(val offset: Int) {
    fun add(n: Int): Int = offset + n
}

fun main() {
    val l: (Int) -> Int = { it * 2 }
    println(l is Function1<*, *>)
    println(l is Function2<*, *, *>)
    println(::add is Function2<*, *, *>)
    println((::add as Function2<Int, Int, Int>)(1, 2))
    println((l as Function1<Int, Int>)(4))

    val erased = identity(returnedLambda())
    println(erased is Function1<*, *>)
    println(erased is Function0<*>)
    println((erased as Function1<Int, Int>)(5))
    println(erased as? Function2<*, *, *> == null)
    val erasedRef = identity(returnedReference())
    println(erasedRef is Function2<*, *, *>)
    println((erasedRef as Function2<Int, Int, Int>)(3, 4))
    try {
        erasedRef as Function1<*, *>
        println("bad cast accepted")
    } catch (e: ClassCastException) {
        println("wrong arity rejected")
    }

    val zero: () -> Int = { 7 }
    val two: (Int, Int) -> Int = { a, b -> a + b }
    val six: (Int, Int, Int, Int, Int, Int) -> Int = { a, b, c, d, e, f -> a + b + c + d + e + f }
    println(identity(zero) is Function0<*>)
    println(identity(two) is Function2<*, *, *>)
    println(identity(six) is Function6<*, *, *, *, *, *, *>)
    println(identity(six) is Function5<*, *, *, *, *, *>)
    println((identity(zero) as Function0<Int>)())
    println((identity(two) as Function2<Int, Int, Int>)(2, 3))
    println(zero())
    println(two(2, 3))
    println(six(1, 2, 3, 4, 5, 6))

    val receiver: String.(Int) -> String = { n -> this + n }
    println(identity(receiver) is Function2<*, *, *>)
    println(identity(receiver) is Function1<*, *>)
    println(receiver("x", 3))
    val extension = String::appendNumber
    println(identity(extension) is Function2<*, *, *>)
    val bound = Adder(10)::add
    val unbound = Adder::add
    println(identity(bound) is Function1<*, *>)
    println(identity(unbound) is Function2<*, *, *>)
    println(identity(bound) is Function2<*, *, *>)
    println((identity(bound) as Function1<Int, Int>)(2))
    println((identity(unbound) as Function2<Adder, Int, Int>)(Adder(20), 2))
    println((identity(Adder(30)::add) as Function1<Int, Int>)(2))

    val offset = 3
    val capturing: (Int) -> Int = { it + offset }
    println(identity(capturing) is Function1<*, *>)
    println(identity(capturing) is Function2<*, *, *>)
    println(capturing(4))
    val nothing: Any? = null
    println(nothing is Function1<*, *>)
    println(nothing is Function1<*, *>?)
    println(identity(123) is Function1<*, *>)
    println(identity("x") as? Function1<*, *> == null)
    println(listOf(1, 2).map { it * 2 })
    println(listOf(1, 2).map(Adder(3)::add))
}
