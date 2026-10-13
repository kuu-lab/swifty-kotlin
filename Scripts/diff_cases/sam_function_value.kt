// KUU-1972: function values adapt to SAM parameters through ordinary member resolution.
fun interface Action { fun run(n: Int): Int }
interface S { fun choose(block: Action): Int }
class Service : S {
    override fun choose(block: Action): Int = block.run(7)
}
fun choose(block: (Int) -> Int): String = "outer"
fun S.read(action: (Int) -> Int): Int = choose(action)
fun explicit(s: S, action: (Int) -> Int): Int = s.choose(action)
fun use(block: Action): Int = block.run(3)
fun makeAction(offset: Int): (Int) -> Int = { n -> n + offset }
fun interface WideAction { fun run(n: Int): Any }
fun wide(block: WideAction): Any = block.run(4)
fun interface TextAction { fun run(text: String): String }
fun text(block: TextAction): String = block.run("SAM")
fun interface GenericAction<T> { fun run(value: T): T }
fun <T> generic(block: GenericAction<T>, value: T): T = block.run(value)
fun doubleInt(value: Int): Int = value * 2
fun main() {
    val s: S = Service()
    val offset = 5
    val action: (Int) -> Int = { n -> n + offset }
    println(s.read(action))
    println(explicit(s, action))
    println(use(action))
    println(use(block = action))
    println(use(makeAction(9)))
    println(s.choose { n -> n * 2 })
    println(wide(action))
    val general: (Any) -> Int = { n -> (n as Int) + offset }
    println(use(general))
    val suffix = "!"
    val textAction: (String) -> String = { value -> value + suffix }
    println(text(textAction))
    val throwing: (Int) -> Int = { n -> throw IllegalStateException("sam") }
    try {
        use(throwing)
    } catch (e: IllegalStateException) {
        println("caught")
    }
    println(generic(::doubleInt, 7))
    println(generic(action, 7))
}
