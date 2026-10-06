// KUU-1294: local nominals must retain the member extension dispatch receiver.
open class OBase(protected val off: Int) {
    protected fun helper(): Int = 3
}
class ODerived : OBase(10) {
    fun Int.make(): Int {
        val o = object {
            fun read(): Int = off
            fun read2(): Int = helper()
        }
        return this + o.read() + o.read2()
    }
    fun Int.inherited(): Int {
        val o = object : OBase(1) {
            fun read(): Int = off + this@ODerived.off
        }
        return this + o.read()
    }
    fun Int.local(): Int {
        class Local { fun read(): Int = off + helper() }
        return this + Local().read()
    }
    fun use() {
        println(2.make())
        println(2.inherited())
        println(2.local())
    }
}
fun main() { ODerived().use() }
