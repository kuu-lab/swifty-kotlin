class ExceptionBuilder {
    private val names: MutableSet<String> = HashSet()
    var count: Int = 0
    fun element(name: String, suffix: String = "") {
        require(names.add(name + suffix)) { "duplicate:$name$suffix" }
        count += 1
    }
    fun fail(message: String = "method") { throw IllegalArgumentException(message) }
}
fun build(vararg values: Int, action: ExceptionBuilder.() -> Unit = {}): Int {
    val builder = ExceptionBuilder()
    builder.action()
    return builder.count
}
fun invokePlain(action: () -> Int): Int = action()
fun invokeUnary(value: Int, action: (Int) -> Int): Int = action(value)
fun invokeReceiver(action: ExceptionBuilder.() -> Int): Int = ExceptionBuilder().action()
fun main() {
    val captured = "x"
    var finalized = false
    try { build(1) { element(captured); element(captured) }; error("accepted duplicate") }
    catch (e: IllegalArgumentException) { check(e.message == "duplicate:x"); println("captured:source:default:require") }
    finally { finalized = true }
    check(finalized)
    try { build { element(captured); element(captured) }; error("accepted empty vararg duplicate") }
    catch (e: IllegalArgumentException) { check(e.message == "duplicate:x"); println("captured:empty-vararg") }
    try { build(1) { fail(captured) }; error("accepted throwing method") }
    catch (e: IllegalArgumentException) { check(e.message == captured); println("captured:explicit-method") }
    try { build(1) { element("plain"); element("plain") }; error("accepted noncaptured duplicate") }
    catch (e: IllegalArgumentException) { check(e.message == "duplicate:plain"); println("noncaptured:source:require") }
    try { invokePlain { error(captured) }; error("accepted throwing plain lambda") }
    catch (e: IllegalStateException) { check(e.message == captured); println("captured:plain") }
    try { invokeUnary(1) { ExceptionBuilder().fail(captured); it }; error("accepted throwing unary lambda") }
    catch (e: IllegalArgumentException) { check(e.message == captured); println("captured:unary:source") }
    try { listOf(1).map { ExceptionBuilder().fail(captured); it }; error("accepted throwing collection lambda") }
    catch (e: IllegalArgumentException) { check(e.message == captured); println("captured:collection:source") }
    check(build(1, 2, 3) { element(captured); element("second") } == 2)
    val seed = 7
    check(invokePlain { seed + 2 } == 9)
    check(invokeUnary(3) { it + seed } == 10)
    check(invokeReceiver { seed + 2 } == 9)
    check(listOf(1, 2).map { it + seed }.joinToString() == "8, 9")
    println("normal:captured:side-effects:collections")
}
