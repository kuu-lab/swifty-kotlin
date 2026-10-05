class C {
    companion object {
        val log = mutableListOf<String>()
        var count = 0
        fun create() = C()
    }

    // KUU-1056: from inside the declaring class, member calls and operator
    // desugars on companion members must resolve exactly like reads do.
    fun size() = log.size
    fun mutate() { log.add("m") }
    fun call() = create()
    fun inc() { count++ }
    fun dec() { count-- }
    fun qualifiedMutate() { C.log.add("q") }
    fun qualifiedInc() { C.count++ }
    fun companionInc() { Companion.count++ }
    fun companionMutate() { Companion.log.add("c") }
    fun assign(v: Int) { count = v }
    fun compoundAssign(v: Int) { count += v }
    fun readCount() = count
}

fun main() {
    val c = C().call()
    c.mutate()
    println(c.size())
    c.inc()
    println(c.readCount())
    c.dec()
    c.qualifiedMutate()
    println(c.size())
    c.assign(10)
    c.compoundAssign(5)
    println(c.readCount())
    c.qualifiedInc()
    c.companionInc()
    println(c.readCount())
    c.companionMutate()
    println(C.log)
    println(C.create() is C)
    C.count++
    println(C.count)
}
