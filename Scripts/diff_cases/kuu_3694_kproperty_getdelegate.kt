// DIFF_CANDIDATE_ONLY: on the JVM, `::prop.getDelegate()` and `p.getDelegate()`
// raise IllegalPropertyDelegateAccessException because the generated $delegate
// field is private (unless kotlin.reflect.jvm.isAccessible is set first). The
// native runtime has no reflection accessibility checks and answers the
// delegate directly — the ticket's "null or delegate instance" contract
// (KUU-3694). Non-delegated and local delegated properties still answer null,
// exactly like the JVM.
// DIFF_CANDIDATE_ONLY_EXPECTED_OUTPUT: kuu_3694_kproperty_getdelegate.expected.stdout
import kotlin.reflect.KProperty
import kotlin.reflect.KProperty0
import kotlin.reflect.KProperty1
import kotlin.reflect.KMutableProperty0

object D {
    var sawGet = false
    var sawSet = false
    operator fun getValue(t: Any?, p: KProperty<*>): String {
        val d = (p as KProperty0<*>).getDelegate()
        if (d === D) sawGet = true
        return "v"
    }
    operator fun setValue(t: Any?, p: KProperty<*>, v: String) {
        val d = (p as KMutableProperty0<*>).getDelegate()
        if (d === D) sawSet = true
    }
}

var x: String by D
var y: String = "n"

// One delegate instance per Owner, so the delegate handle must come from the
// instance's own field — two different receivers must observe two different
// delegates through the shared cached KProperty stub.
class MD {
    @Suppress("UNCHECKED_CAST")
    operator fun getValue(t: Owner, p: KProperty<*>): String {
        val d = (p as KProperty1<Owner, String>).getDelegate(t)
        return if (d === this) "self" else "other"
    }
    operator fun setValue(t: Owner, p: KProperty<*>, v: String) {}
}

class Owner {
    val m: String by MD()
    val n: String = "nn"
}

// A local delegated property's KProperty has no bound delegate on the JVM
// (PropertyReference0Impl answers null), and so does ours.
class LD {
    operator fun getValue(t: Any?, p: KProperty<*>): String {
        val d = (p as KProperty0<*>).getDelegate()
        return if (d == null) "null" else "non-null"
    }
}

fun localProbe(): String {
    val s: String by LD()
    return s
}

fun main() {
    println("x_ref:" + (::x.getDelegate() === D))
    println("y_null:" + (::y.getDelegate() == null))
    x = "z"
    println(x)
    println("get_saw:" + D.sawGet)
    println("set_saw:" + D.sawSet)
    val o1 = Owner()
    val o2 = Owner()
    println("m_get:" + o1.m)
    println("unbound:" + (Owner::m.getDelegate(o1) === o1::m.getDelegate()))
    println("distinct:" + (Owner::m.getDelegate(o1) !== Owner::m.getDelegate(o2)))
    println("n_null:" + (o1::n.getDelegate() == null))
    println("local:" + localProbe())
}
