interface Counter {
    var count: Int
    fun inc() { count++ }
    fun incPlus() { count += 1 }
    fun dec() { count-- }
    fun incPrefix(): Int { ++count; return count }
    fun incPostfix(): Int { return count++ }
    fun setIt(v: Int) { count = v }
}
abstract class AE {
    abstract var count: Int
    fun inc() { count++ }
    fun incPlus() { count += 1 }
    fun dec() { count-- }
    fun setIt(v: Int) { count = v }
}
class CI : Counter { override var count = 0 }
class CA : AE() { override var count = 0 }
class W(private val c: Counter) : Counter by c
open class OB {
    open var count = 0
    fun inc() { count++ }
    fun incPlus() { count += 1 }
    fun setIt(v: Int) { count = v }
}
class OS : OB() { override var count = 100 }
open class OC {
    open var count = 0
        get() = field
        set(v) { field = v * 2 }
    fun setIt(v: Int) { count = v }
    fun bump() { count += 1 }
}
class OCS : OC() { override var count = 100 }

fun main() {
    val a = CI(); a.inc(); println(a.count)
    val b = CI(); b.incPlus(); println(b.count)
    val c = CI(); c.dec(); println(c.count)
    println(CI().incPrefix())
    val p = CI(); println(p.incPostfix()); println(p.count)
    val ci = CI(); ci.setIt(9); println(ci.count)
    val d = CA(); d.inc(); println(d.count)
    val e = CA(); e.incPlus(); println(e.count)
    val f = CA(); f.dec(); println(f.count)
    val g = CA(); g.setIt(41); println(g.count)
    val w = W(CI()); w.inc(); println(w.count)
    val os = OS(); os.inc(); println(os.count)
    val os2 = OS(); os2.incPlus(); println(os2.count)
    val os3 = OS(); os3.setIt(7); println(os3.count)
    val oc = OC(); oc.bump(); println(oc.count)
    val oc2 = OC(); oc2.setIt(5); println(oc2.count)
    val ocs = OCS(); ocs.bump(); println(ocs.count)
    val ocs2 = OCS(); ocs2.setIt(9); println(ocs2.count)
}
