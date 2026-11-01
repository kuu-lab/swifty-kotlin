import kotlin.reflect.KParameter

// KUU-4091 — KProperty.getter / KMutableProperty.setter are accessor-owned
// KCallables on the JVM: member (descriptor-backed) accessors serve their own
// parameter boxes, while top-level/extension accessors share the property's
// receiver parameters and only the setter's value parameter is accessor-owned.

class C(val v: Int) {
    var w: Int = 0
    var u: Int = 0
        set(v) { field = v }
}
val String.ext: Int get() = length
var String.mext: Int
    get() = length
    set(v) {}
var topVar = 0
val topVal = 1

fun main() {
    val p = C::v
    // Accessors are cached on the reference instance.
    println("getter identity: ${p.getter === p.getter}")
    println("setter identity: ${C::w.setter === C::w.setter}")
    val q = C::w
    println("setter identity memo: ${q.setter === q.setter}")
    // Member getter parameters are accessor-owned, not the property's boxes.
    println("member getter refeq: ${p.getter.parameters[0] === p.parameters[0]}")
    println("member getter eq: ${p.getter.parameters[0] == p.parameters[0]}")
    println("member getter list refeq: ${p.getter.parameters === p.parameters}")
    println("member getter self refeq: ${p.getter.parameters[0] === p.getter.parameters[0]}")
    println("member getter kind: ${p.getter.parameters[0].kind}")
    println("member getter index: ${p.getter.parameters[0].index}")
    // Member setter parameters are accessor-owned too (receiver and value).
    println("member setter refeq: ${q.setter.parameters[0] === q.parameters[0]}")
    println("member setter eq: ${q.setter.parameters[0] == q.parameters[0]}")
    println("member setter size: ${q.setter.parameters.size}")
    println("member setter value index: ${q.setter.parameters[1].index}")
    println("member setter value kind: ${q.setter.parameters[1].kind}")
    println("member setter value name: ${q.setter.parameters[1].name}")
    // An explicitly declared setter keeps its declared parameter name.
    println("declared setter value name: ${C::u.setter.parameters[1].name}")
    // Top-level/extension accessors share the property's parameter boxes.
    val e = String::mext
    println("ext getter list refeq: ${e.getter.parameters === e.parameters}")
    println("ext getter refeq: ${e.getter.parameters[0] === e.parameters[0]}")
    println("ext getter eq: ${e.getter.parameters[0] == e.parameters[0]}")
    println("ext setter receiver refeq: ${e.setter.parameters[0] === e.parameters[0]}")
    println("ext setter receiver eq: ${e.setter.parameters[0] == e.parameters[0]}")
    println("ext setter size: ${e.setter.parameters.size}")
    println("ext setter value index: ${e.setter.parameters[1].index}")
    println("ext setter value name: ${e.setter.parameters[1].name}")
    println("ext getter name: ${String::ext.getter.name}")
    println("ext setter name: ${e.setter.name}")
    // Top-level non-extension accessors.
    println("topVar setter size: ${::topVar.setter.parameters.size}")
    println("topVar setter value name: ${::topVar.setter.parameters[0].name}")
    println("topVal getter size: ${::topVal.getter.parameters.size}")
    // Bound references keep receiver-stripped accessor parameters.
    val c = C(7)
    println("bound getter size: ${c::v.getter.parameters.size}")
    println("bound setter size: ${c::w.setter.parameters.size}")
    println("bound getter list refeq: ${c::v.getter.parameters === c::v.parameters}")
    val s = "hi"
    println("bound ext getter list refeq: ${s::ext.getter.parameters === s::ext.parameters}")
    // KParameter.toString renders "<kind> of fun Owner.`<get|set-x>`(...)"
    // for accessor-owned parameters and "... of val|var Owner.x" for the
    // property's own boxes.
    println("member getter tostring: ${p.getter.parameters[0]}")
    println("member setter params: ${q.setter.parameters}")
    println("member prop param: ${p.parameters[0]}")
    println("ext setter value tostring: ${e.setter.parameters[1]}")
    println("topVar setter params: ${::topVar.setter.parameters}")
    // The accessor's own KCallable shape: `set` returns kotlin.Unit.
    println("getter returnType: ${p.getter.returnType}")
    println("setter returnType: ${q.setter.returnType}")
    // Accessor invocation still works through the new parameter lists.
    println("getter call: ${C::v.getter.call(c)}")
    C::w.setter.call(c, 9)
    println("setter call: ${c.w}")
    e.setter.call("abc", 42)
    println("ext setter call ok")
    // Accessors of equal property references compare equal (the getter and
    // setter stay distinct from each other and from the property).
    println("getter eq xrefs: ${C::v.getter == C::v.getter}")
    println("setter eq xrefs: ${C::w.setter == C::w.setter}")
    println("getter vs setter eq: ${C::w.getter == C::w.setter}")
    println("getter vs prop eq: ${C::v.getter == C::v}")
}
