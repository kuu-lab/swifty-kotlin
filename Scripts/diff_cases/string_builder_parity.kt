fun <T : Comparable<T>> compareBuilders(first: T, second: T): Int = first.compareTo(second)

fun main() {
    val builder = StringBuilder("aBcB")
    println(builder.indexOf('B'))
    println(builder.indexOf('b', ignoreCase = true))
    println(builder.indexOf('B', 2))
    println(builder.indexOf('z', -5))
    println(builder.lastIndexOf('B'))
    println(builder.lastIndexOf('b', ignoreCase = true))
    println(builder.lastIndexOf('B', 2))
    println(builder.lastIndexOf('B', -1))
    println(builder.indexOf("Bc"))
    println(builder.lastIndexOf("B"))
    println(builder.indexOfFirst { it == 'c' })
    val nullableBuilder: StringBuilder? = builder
    println(nullableBuilder?.indexOf('B'))

    val comparable: Comparable<StringBuilder> = StringBuilder("ab")
    println(comparable.compareTo(StringBuilder("az")))
    println(compareBuilders(StringBuilder("ab"), StringBuilder("abcd")))
    println(StringBuilder("").compareTo(StringBuilder("abc")))
    println(StringBuilder("\uD800").compareTo(StringBuilder("\uDC00")))
    println(compareBuilders(StringBuilder("\uD800\uDC00"), StringBuilder("\uE800")))
    println(StringBuilder("ab") < StringBuilder("ac"))
    println(listOf(StringBuilder("b"), StringBuilder("a"), StringBuilder("ab")).sorted())
    println(listOf(StringBuilder("\uE800"), StringBuilder("\uD800\uDC00")).sorted().first().length)
    println(compareValues(StringBuilder("ab"), StringBuilder("az")))
    println(maxOf(StringBuilder("a"), StringBuilder("b")))
    println((builder as Any) is Comparable<*>)
    val mutable = StringBuilder("ab")
    println(compareBuilders(mutable, StringBuilder("ab")))
    mutable.append("zz")
    println(compareBuilders(mutable, StringBuilder("ab")))

    val nulls = StringBuilder()
    nulls.append(null as String?)
    nulls.append(null as CharSequence?)
    nulls.append(null as Any?)
    nulls.append(charArrayOf('x', 'y'))
    println(nulls)
    try {
        nulls.append(null as CharArray?)
        println("missing exception")
    } catch (expected: NullPointerException) {
        println("NullPointerException")
    }
    println(nulls)
}
