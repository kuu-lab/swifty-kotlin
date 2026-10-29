// KUU-3193: a `by lazy` delegate body inside an anonymous object must read
// captured outer values (function parameters, local vars, `this` members)
// through the object's capture fields — including when the anonymous object
// is itself nested inside another nominal's member body, where the enclosing
// object must forward the inner literal's registered capture set
// (JetBrains delegatedProperty/lazyInAnonymousObject.kt, KT-89384).
interface Matcher { fun check(): Boolean }

// Ticket shape: top-level function parameter captured by lazy.
fun topLevel(pattern: String): Matcher = object : Matcher {
    private val suffix: String? by lazy { pattern.takeIf { it == "x" } }
    override fun check() = suffix != null
}

// JetBrains shape: member-function parameter captured by lazy.
class Config(val tag: String) {
    fun createMatcher(pattern: String): Matcher = object : Matcher {
        private val suffix: String? by lazy { pattern.takeIf { it == "x" } }
        override fun check() = suffix != null
    }
}

// Param + mutable local var + `this` member across several lazy properties.
class Holder(val tag: String) {
    fun multi(pattern: String): Matcher {
        var extra = "e"
        return object : Matcher {
            private val a: String? by lazy { pattern.takeIf { it == "x" } }
            private val b: String? by lazy { extra.takeIf { it == "e" } }
            private val c: String? by lazy { tag.takeIf { it == "T" } }
            override fun check() = a != null && b != null && c != null
        }
    }
}

interface Outer { fun inner(): Matcher }

// Anonymous object nested inside another anonymous object's member function:
// the outer literal must capture `pattern` so the inner literal's lazy
// delegate can reload it from its own capture field.
fun nestedLazy(pattern: String): Matcher = object : Outer {
    override fun inner(): Matcher = object : Matcher {
        private val suffix: String? by lazy { pattern.takeIf { it == "x" } }
        override fun check() = suffix != null
    }
}.inner()

class IntBox(var v: String) {
    operator fun getValue(thisRef: Any?, property: kotlin.reflect.KProperty<*>): String = v
}

// Nested literal: delegate-expression argument, custom accessor body, and
// `init {}` block all see the same outer parameter through capture fields.
fun nestedOtherBodies(tag: String): Matcher = object : Outer {
    override fun inner(): Matcher = object : Matcher {
        private val d: String by IntBox(tag)
        private val g: String get() = tag
        private var probe: String? = null
        init { probe = tag.takeIf { it == "x" } }
        override fun check() = d == "x" && g == "x" && probe != null
    }
}.inner()

// Non-anonymous named local class — control shape whose captures flow
// through `<init>` instead of construction-site fields.
fun namedLocalClass(pattern: String): Matcher {
    class Local : Matcher {
        private val suffix: String? by lazy { pattern.takeIf { it == "x" } }
        override fun check() = suffix != null
    }
    return Local()
}

fun main() {
    println(if (topLevel("x").check()) "OK" else "FAIL")
    println(if (Config("T").createMatcher("x").check()) "OK" else "FAIL")
    println(if (Holder("T").multi("x").check()) "OK" else "FAIL")
    println(if (nestedLazy("x").check()) "OK" else "FAIL")
    println(if (nestedOtherBodies("x").check()) "OK" else "FAIL")
    println(if (namedLocalClass("x").check()) "OK" else "FAIL")
}
