import Testing

extension BundledStdlibExecutionTests {
    /// KUU-4030: a `var` property obtained through `memberProperties`/
    /// `declaredMemberProperties` reflects as `KMutablePropertyN` (and a
    /// `val` as `KPropertyN`) like the JVM — the member reflection handle
    /// previously dropped mutability/arity metadata, so
    /// `p is KMutableProperty` answered false.
    @Test(arguments: [true, false])
    func memberPropertyVarReflectsAsKMutableProperty(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            """
            import kotlin.reflect.full.*
            import kotlin.reflect.*

            class C(val c1: Int, var c2: String)

            fun main() {
                val p = C::class.memberProperties.first { it.name == "c2" }
                println(p is KMutableProperty<*>)
                println(p is KMutableProperty1<*, *>)
                println(p is KProperty1<*, *>)
                println(p is KProperty<*>)
                val v = C::class.memberProperties.first { it.name == "c1" }
                println(v is KMutableProperty<*>)
                println(v is KMutableProperty1<*, *>)
                println(v is KProperty1<*, *>)
                println(v is KProperty<*>)
                val d = C::class.declaredMemberProperties.first { it.name == "c2" }
                println(d is KMutableProperty<*>)
                println(d is KMutableProperty1<*, *>)
                println((p as? KMutableProperty<*>) != null)
                println((v as? KMutableProperty<*>) == null)
                println(C::c2 is KMutableProperty1<*, *>)
                println(C::c1 !is KMutableProperty<*>)
            }
            """,
            expectedOutput: String(repeating: "true\n", count: 4)
                + "false\nfalse\ntrue\ntrue\n"
                + String(repeating: "true\n", count: 6),
            moduleName: "MemberPropertyVarReflectsAsKMutableProperty",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }

    /// KUU-4030: a member extension property reflects as the arity-2
    /// `KMutableProperty2`/`KProperty2` its two receivers (dispatch +
    /// extension) imply, matching the unbound `C::ext` reference shape.
    @Test(arguments: [true, false])
    func memberExtensionPropertyReflectsMutableArity(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            """
            import kotlin.reflect.full.*
            import kotlin.reflect.*

            class C(val c1: Int, var c2: String) {
                var String.extVar: Int
                    get() = length
                    set(value) {}
                val String.extVal: Int
                    get() = length
            }

            fun main() {
                val e = C::class.memberProperties.first { it.name == "extVar" }
                println(e is KMutableProperty2<*, *, *>)
                println(e is KMutableProperty<*>)
                println(e is KMutableProperty1<*, *>)
                println(e is KProperty<*>)
                val ev = C::class.memberProperties.first { it.name == "extVal" }
                println(ev is KMutableProperty<*>)
                println(ev is KProperty2<*, *, *>)
                println(ev is KProperty1<*, *>)
            }
            """,
            expectedOutput: "true\ntrue\nfalse\ntrue\nfalse\ntrue\nfalse\n",
            moduleName: "MemberExtensionPropertyReflectsMutableArity",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }
}
