// lateinit storage must start as "not initialized" in every member context,
// and a lateinit assigned from a virtual call during super init must survive
// the subclass's own initialization.

abstract class Base {
    init { setup() }
    abstract fun setup()
}

class FromSuperInit : Base() {
    lateinit var s: String
    val after = "after"
    override fun setup() { s = "ready" }
}

class FromSecondary : Base {
    lateinit var s: String
    constructor() : super()
    override fun setup() { s = "secondary" }
}

class Plain {
    lateinit var s: String
    fun ready() = this::s.isInitialized
}

object FromSuperInitObject : Base() {
    lateinit var s: String
    override fun setup() { s = "object" }
}

class Box(val v: Int)

object Cfg {
    lateinit var box: Box
    fun ready() = this::box.isInitialized
}

class Host {
    companion object {
        lateinit var name: String
        fun ready() = this::name.isInitialized
        fun read() = name
        fun write(v: String) { name = v }
    }
}

interface Probe {
    fun ready(): Boolean
    fun read(): String
    fun write(v: String)
}

fun main() {
    val f = FromSuperInit()
    println(f.s)
    println(f.after)
    println(FromSecondary().s)
    println(FromSuperInitObject.s)
    val literal = object : Base() {
        lateinit var s: String
        override fun setup() { s = "literal-super" }
        fun read() = s
    }
    println(literal.read())

    try { println(Plain().s) } catch (e: UninitializedPropertyAccessException) { println(e.message) }
    val p = Plain()
    println(p.ready())
    try { println(p.s) } catch (e: UninitializedPropertyAccessException) { println(e.message) }
    p.s = "set"
    println(p.ready())
    println(p.s)

    println(Cfg.ready())
    try { println(Cfg.box.v) } catch (e: UninitializedPropertyAccessException) { println(e.message) }
    Cfg.box = Box(7)
    println(Cfg.ready())
    println(Cfg.box.v)

    println(Host.ready())
    try { println(Host.read()) } catch (e: UninitializedPropertyAccessException) { println(e.message) }
    Host.write("host")
    println(Host.ready())
    println(Host.read())

    val probe = object : Probe {
        lateinit var v: String
        override fun ready() = this::v.isInitialized
        override fun read() = v
        override fun write(v: String) { this.v = v }
    }
    println(probe.ready())
    try { println(probe.read()) } catch (e: UninitializedPropertyAccessException) { println(e.message) }
    probe.write("literal")
    println(probe.ready())
    println(probe.read())
}
