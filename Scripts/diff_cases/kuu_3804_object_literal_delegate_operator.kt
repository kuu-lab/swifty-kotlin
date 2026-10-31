// KUU-3804: an anonymous `object` used as a `by` delegate expression keeps
// member semantics for its `operator` functions. The property-declaration
// delegate-body fallback must not re-parse the object body as a statement
// block, where `operator fun` members read as ineligible local functions
// (KSWIFTK-SEMA-0439).
import kotlin.reflect.*

var x: String by object {
    var stored = "init"
    operator fun getValue(t: Any?, p: KProperty<*>): String = stored
    operator fun setValue(t: Any?, p: KProperty<*>, v: String) { stored = v }
}

fun main() {
    println(x)
    x = "written"
    println(x)
}
