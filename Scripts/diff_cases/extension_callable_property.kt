class D(
    private val convertTo: Int.() -> String,
    private val convert: String.() -> Int
) {
    fun f(i: Int): String = i.convertTo()
    fun g(s: String): Int = s.convert()
    fun all(values: List<Int>): List<String> = values.map { it.convertTo() }
}

class Converter<From, To>(private val convert: From.() -> To) {
    fun one(element: From): To = element.convert()
    fun all(elements: List<From>): List<To> = elements.map { it.convert() }
}

class Reader<T> {
    fun String.echo(value: T): T = value
    fun read(text: String, value: T): T = text.echo(value)
}

class Owner(private val offset: Int) {
    private val action: Int.(Int) -> Int = { n -> this + n + offset }
    fun use(i: Int): Int = i.action(3)
}

var reads = 0
val tracked: String.(Int) -> String
    get() {
        reads += 1
        return { n -> this + n.toString() }
    }

fun local(action: Int.(Int) -> Int): Int = 7.action(4)

fun main() {
    val d = D({ "n=" + this.toString() }, { this.length })
    println(d.f(42))
    println(d.g("hello"))
    println(d.all(listOf(1, 2, 3)))
    val generic = Converter<Int, String>({ "g=" + this.toString() })
    println(generic.one(8))
    println(generic.all(listOf(4, 5)))
    println(Reader<Int>().read("receiver", 42))
    println(Owner(10).use(2))
    println(local { n -> this + n })
    val offset = 5
    val action: Int.() -> Int = { this + offset }
    println(9.action())
    println(listOf(1, 2).map { it.action() })
    val nullable: String?.() -> Int = { if (this == null) -1 else this.length }
    val absent: String? = null
    println(absent.nullable())
    println("ok".nullable())
    println(absent?.tracked(1))
    println(reads)
    println("x".tracked(2))
    println(reads)
    val present: String? = "y"
    println(present?.tracked(3))
    println(reads)
}
