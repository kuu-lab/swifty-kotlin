fun <T> id(value: T): T & Any = value as (T & Any)

var evaluations = 0

fun <T> produce(value: T): T {
    evaluations++
    return value
}

fun <T : CharSequence?> castWithUpperBound(value: T): T & Any = produce(value) as (T & Any)

fun main() {
    println(id(42))
    println(id("OK"))
    println(try { id<String?>(null); "NO_THROW" } catch (e: NullPointerException) { "NPE" })

    evaluations = 0
    println(castWithUpperBound<String?>("OK"))
    println("evaluations:$evaluations")

    evaluations = 0
    println(try { castWithUpperBound<String?>(null); "NO_THROW" } catch (e: NullPointerException) { "NPE" })
    println("evaluations:$evaluations")
}
