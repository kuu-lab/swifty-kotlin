// KUU-3839 / KT-78073: a `fun interface` SAM constructor used directly as a
// property delegate (`by ReadOnlyProperty { ... }`) must infer its type
// arguments from the delegate convention — the getValue `thisRef` argument
// binds in-position parameters, the lambda return binds the rest.

import kotlin.reflect.KProperty

fun interface ReadOnlyProperty<in T, out V> {
    operator fun getValue(thisRef: T, property: KProperty<*>): V
}

val topLevel by ReadOnlyProperty { _, property -> property }

fun box(): String {
    // Local delegated properties: type arguments come from the lambda return
    // and the local delegate's thisRef (KT-78073 regression shape).
    val property1 by ReadOnlyProperty { _, property -> property }
    val property2 by ReadOnlyProperty { _, property -> property }

    val property1Ref = property1
    if (property1Ref.name != "property1") return "Fail 1: ${property1Ref.name}"

    val property2Ref = property2 // invokes the property2 delegate
    if (property1Ref.name != "property1") return "Fail 2: ${property1Ref.name}"
    if (property2Ref.name != "property2") return "Fail 3: ${property2Ref.name}"

    property1 // invokes the property1 delegate
    if (property1Ref.name != "property1") return "Fail 4: ${property1Ref.name}"
    if (property2Ref.name != "property2") return "Fail 5: ${property2Ref.name}"

    return "OK"
}

class Holder {
    fun marker(): String = "member-thisRef"
    // Member delegates bind thisRef to the containing class, so the lambda
    // may call members through the typed receiver.
    val member by ReadOnlyProperty { thisRef, property -> thisRef.marker() + ":" + property.name }
}

fun main() {
    println(box())
    println(topLevel.name)
    println(Holder().member)
}
