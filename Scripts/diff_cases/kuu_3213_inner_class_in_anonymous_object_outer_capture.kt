// KUU-3213: an `inner class` nested inside an anonymous `object` expression
// reaches the enclosing class instance through the literal's captured
// receiver field, which is keyed by a synthetic receiver symbol rather than
// the class symbol -- the `$outer` chain walk must hop through that
// receiver-keyed capture or reads of the outer members observe null.
// Based on JetBrains objects/innerClassInsideAnonymousObject.kt.
class Generic<T>(val t: T) {
    fun foo(): T {
        val o1 = object {
            inner class InnerLocal1 {
                fun bar(): T {
                    val o2 = object { inner class InnerLocal2 { fun baz(): T = t } }
                    return o2.InnerLocal2().baz()
                }
            }
        }
        return o1.InnerLocal1().bar()
    }
}

// Same shape with a named local nominal: the inner class's `$outer` is the
// local class instance, and the outer class is reached through its capture.
class GenericLocal<T>(val t: T) {
    fun foo(): T {
        class L { inner class I { fun v(): T = t } }
        return L().I().v()
    }
}

// A member *call* on the enclosing receiver needs the same chain link that
// the property read does.
class GenericCall<T>(val t: T) {
    fun greet(): String = "g:$t"
    fun foo(): String {
        val o = object {
            inner class I { fun v(): String = greet() }
        }
        return o.I().v()
    }
}

// A qualified `this@Label` read uses the same walk with subtype matching
// disabled; the exact-class receiver capture must still be found.
class GenericQualified<T>(val t: T) {
    fun foo(): T {
        val o = object {
            inner class I { fun v(): T = this@GenericQualified.t }
        }
        return o.I().v()
    }
}

fun main() {
    println(Generic("OK").foo())
    println(GenericLocal("OK").foo())
    println(GenericCall("OK").foo())
    println(GenericQualified("OK").foo())
}
