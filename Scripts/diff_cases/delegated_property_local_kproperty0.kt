// DIFF_JVM
import kotlin.reflect.KProperty
import kotlin.reflect.KProperty0
import kotlin.reflect.KMutableProperty0

// KUU-2947 / JetBrains delegatedProperty/local/localDelegatedPropertyCall.kt:
// a local delegated property hands getValue a KProperty0 (KMutableProperty0
// for `var`) whose get/set/invoke/call/callBy throw a catchable
// UnsupportedOperationException.
class Delegate {
    operator fun getValue(thiz: Any?, prop: KProperty<*>): String =
        (prop as KProperty0<*>).get() as String   // JVM: UnsupportedOperationException
}

fun box() = try { val x by Delegate(); x } catch (e: UnsupportedOperationException) { "OK" }

class Probe {
    operator fun getValue(thiz: Any?, prop: KProperty<*>): String {
        val sb = StringBuilder()
        sb.append(prop is KProperty0<*>)
        try { (prop as KProperty0<*>).invoke(); sb.append("|invoke:-") }
        catch (e: UnsupportedOperationException) { sb.append("|invoke:UOE") }
        try { prop.call(); sb.append("|call:-") }
        catch (e: UnsupportedOperationException) { sb.append("|call:UOE") }
        try { prop.callBy(emptyMap()); sb.append("|callBy:-") }
        catch (e: UnsupportedOperationException) { sb.append("|callBy:UOE") }
        val d = (prop as KProperty0<*>).getDelegate()
        sb.append("|delegate:").append(d == null)
        sb.append("|name:").append(prop.name)
        return sb.toString()
    }
}

class VarProbe {
    operator fun getValue(thiz: Any?, prop: KProperty<*>): String {
        val sb = StringBuilder()
        sb.append(prop is KMutableProperty0<*>).append("|").append(prop is KProperty0<*>)
        @Suppress("UNCHECKED_CAST")
        val mp = prop as KMutableProperty0<String>
        try { mp.set("v"); sb.append("|set:-") }
        catch (e: UnsupportedOperationException) { sb.append("|set:UOE") }
        try { mp.setter.call("v"); sb.append("|setter:-") }
        catch (e: UnsupportedOperationException) { sb.append("|setter:UOE") }
        try { mp.getter.call(); sb.append("|getter:-") }
        catch (e: UnsupportedOperationException) { sb.append("|getter:UOE") }
        return sb.toString()
    }
    operator fun setValue(thiz: Any?, prop: KProperty<*>, v: String) {}
}

class MemberBox {
    // A member delegated property is a KProperty1 — the cast to KProperty0
    // must stay a ClassCastException, not silently succeed.
    val m by Delegate()
}

fun memberBox() = try { MemberBox().m } catch (e: ClassCastException) { "CCE" }

fun main() {
    println(box())
    val p by Probe()
    println(p)
    var q by VarProbe()
    println(q)
    println(memberBox())
}
