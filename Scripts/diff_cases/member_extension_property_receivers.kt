open class PBase(protected val off: Int)

class PDerived : PBase(10) {
    val Int.score: Int
        get() = this + off
    fun use() { println(2.score) }
}

class Scores(private val off: Int) {
    private var stored: Int = 0
    val Int.score: Int
        get() = this + this@Scores.off
    val Int.relay: Int
        get() = score
    var Int.total: Int
        get() = this + stored + off
        set(value) { stored = value - this - off }
    val String.label: String
        get() = this + off
    fun use() {
        println(2.score)
        3.total = 20
        println(3.total)
        3.total += 4
        println(3.total)
        println(stored)
        println("score=".label)
        val n: Int? = 2
        println(n?.score)
        val block = { 3.score }
        println(block())
        println(4.relay)
    }
}

open class VirtualBase {
    protected var stored: Int = 0
    open val Int.score: Int get() = this + 10
    open var Int.total: Int
        get() = this + stored
        set(value) { stored = value - this }
    fun use() {
        println(2.score)
        2.total = 42
        println(2.total)
        2.total += 4
        println(2.total)
        println(stored)
    }
}

class VirtualDerived : VirtualBase() {
    override val Int.score: Int get() = this + 20
    override var Int.total: Int
        get() = this + stored + 20
        set(value) { stored = value - this - 20 }
}

fun main() {
    PDerived().use()
    Scores(7).use()
    Scores(11).use()
    VirtualDerived().use()
}
