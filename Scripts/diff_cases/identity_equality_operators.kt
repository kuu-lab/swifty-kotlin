interface Named {
    fun name(): String
}

class Person(val n: String) : Named {
    override fun name(): String = n
}

fun describe(x: Named?): String {
    if (x !== null) {
        return "named:${x.name()}"
    }
    return "none"
}

fun main() {
    // Interface-typed operands: same reference vs different instances.
    val a: Named = Person("Ann")
    val b: Named = a
    val c: Named = Person("Ann")
    println(a === b)
    println(a !== b)
    println(a === c)
    println(a !== c)

    // Concrete class operands.
    val p1 = Person("Bo")
    val p2 = p1
    val p3 = Person("Bo")
    println(p1 === p2)
    println(p1 === p3)

    // Null identity, including smart-cast through !== null.
    val n1: Named? = null
    println(n1 === null)
    println(n1 !== null)
    println(describe(a))
    println(describe(n1))

    // Chained / nested usage.
    println((a === b) === true)

    // Primitive identity.
    val i1 = 7
    val i2 = 7
    println(i1 === i2)
}
