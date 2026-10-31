// KUU-3803: a bound delegated member property reference on a singleton
// `object` crashed with SIGSEGV on get/set — the generated KProperty
// wrapper invoked the real delegated accessor without its dispatch
// receiver argument (object delegated accessors keep the receiver
// parameter even though their storage is global). Covers the ticket's
// `O::member.set(v)` plus the same wrapper reached through
// List<KProperty<*>> iteration and `as?` casts.
import kotlin.reflect.KMutableProperty0
import kotlin.reflect.KProperty
import kotlin.reflect.KProperty0

object Delegate {
    var log = ""
    operator fun getValue(t: Any?, p: KProperty<*>): String {
        log += "g(${p.name})"
        return "V"
    }
    operator fun setValue(t: Any?, p: KProperty<*>, v: String) {
        log += "s(${p.name}=$v)"
    }
}

object O { var member: String by Delegate }
object P { val ro: String by Delegate }

fun main() {
    val s: KMutableProperty0<String> = O::member
    s.set("A")
    println(s.get())
    val r: KProperty0<String> = P::ro
    println(r.get())
    val props: List<KProperty<*>> = listOf(O::member, P::ro)
    for (p in props) {
        (p as? KMutableProperty0<String>)?.set("L")
        println((p as? KProperty0<String>)?.get())
    }
    println(Delegate.log)
    println("OK")
}
