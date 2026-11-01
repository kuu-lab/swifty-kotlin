#if canImport(Testing)
import Testing

extension BundledStdlibExecutionTests {
    /// KUU-851 regression: source-backed callable properties must dispatch
    /// through their interface getter for user implementations.
    @Test
    func testUserCallableImplementationsDispatchPropertiesThroughInterfaces() throws {
        try compileAndRunKotlin(
            """
            import kotlin.reflect.KCallable
            import kotlin.reflect.KProperty
            import kotlin.reflect.KType
            import kotlin.reflect.KParameter
            import kotlin.reflect.KTypeParameter
            import kotlin.reflect.KVisibility

            abstract class CallableMetadata : KCallable<Int> {
                override val annotations = emptyList<Annotation>()
                override val parameters = emptyList<KParameter>()
                override val typeParameters = emptyList<KTypeParameter>()
                override val visibility = KVisibility.PUBLIC
                override val isFinal = true
                override val isOpen = false
                override val isAbstract = false
                override val isSuspend = false
                override val returnType: KType
                    get() = throw UnsupportedOperationException()
                override fun call(vararg args: Any?): Int = throw UnsupportedOperationException()
                override fun callBy(args: Map<KParameter, Any?>): Int = throw UnsupportedOperationException()
            }

            class CallableImpl(override val name: String) : CallableMetadata()

            class PropertyImpl(override val name: String) : CallableMetadata(), KProperty<Int> {
                override val isLateinit = false
                override val isConst = false
                override val getter: KProperty.Getter<Int>
                    get() = throw UnsupportedOperationException()
            }

            fun main() {
                println(CallableImpl("callable-direct").name)
                val callable: KCallable<Int> = CallableImpl("callable-interface")
                println(callable.name)
                try {
                    callable.returnType
                    println("callable returnType did not throw")
                } catch (e: Throwable) {
                    println("callable returnType threw")
                }

                println(PropertyImpl("property-direct").name)
                val property: KProperty<Int> = PropertyImpl("property-interface")
                println(property.name)
                try {
                    property.returnType
                    println("property returnType did not throw")
                } catch (e: Throwable) {
                    println("property returnType threw")
                }
            }
            """,
            expectedOutput: [
                "callable-direct",
                "callable-interface",
                "callable returnType threw",
                "property-direct",
                "property-interface",
                "property returnType threw",
            ].joined(separator: "\n") + "\n",
            allowDefaultStdlibLibrary: false
        )
    }

    /// Runtime KProperty stubs (delegate `property:` arguments) register their
    /// KCallable getters through the runtime itable. `name` returns a Kotlin
    /// String, so the registered bridge must satisfy the flat-string sret ABI —
    /// a regression returning the raw handle instead corrupted the receiver's
    /// stack slot and made `Map.getValue`'s `property.name` lookup produce
    /// garbage keys ("Key <pointer> is missing in the map").
    @Test
    func testRuntimeKPropertyStubsDispatchNameThroughInterface() throws {
        try compileAndRunKotlin(
            """
            import kotlin.reflect.KProperty

            class D {
                operator fun getValue(thisRef: Any?, property: KProperty<*>): Int {
                    println(property.name)
                    return 1
                }
            }

            fun main() {
                val v: Int by D()
                println(v)
                val m: Map<String, Int> = mapOf("delegatedValue" to 42)
                val delegatedValue: Int by m
                println(delegatedValue)
            }
            """,
            expectedOutput: "v\n1\n42\n",
            allowDefaultStdlibLibrary: false
        )
    }

    /// Runtime-registered `KCallable.name` itable shims return the raw String
    /// handle, but the itable call site expects the flat String aggregate.
    /// x86-64 SysV happens to pass that result through a hidden first-argument
    /// pointer the shim can detect; AArch64 returns it in x0-x3, so property
    /// references read through `KProperty<*>`/`KCallable<*>` crashed there.
    /// The same interface call site must still dispatch user implementations.
    @Test
    func testInterfaceTypedCallableNameMixesRuntimeReferencesAndUserImplementations() throws {
        try compileAndRunKotlin(
            """
            import kotlin.reflect.KCallable
            import kotlin.reflect.KMutableProperty
            import kotlin.reflect.KProperty
            import kotlin.reflect.KType

            class Counter(var count: Int)

            class NamedCallable(override val name: String) : KCallable<Int> {
                override val returnType: KType
                    get() = throw UnsupportedOperationException()
            }

            fun describe(callable: KCallable<*>): String = callable.name

            fun main() {
                val ref: KProperty<*> = Counter::count
                println(ref.name)
                val mutableRef: KMutableProperty<*> = Counter::count
                println(mutableRef.name)
                val nullableRef: KProperty<*>? = Counter(2)::count
                println(nullableRef?.name)
                val callables: List<KCallable<*>> = listOf(Counter::count, NamedCallable("user"))
                println(callables.map { describe(it) })
            }
            """,
            expectedOutput: "count\ncount\ncount\n[count, user]\n",
            allowDefaultStdlibLibrary: false
        )
    }

    /// KUU-4017: `KParameter.annotations` is declared on `KAnnotatedElement`,
    /// outside the `__kk_kparameter_*` member fast path, so runtime KParameter
    /// boxes reached the source interface getter and died on the
    /// KAnnotatedElement cast (`ClassCastException` → KSWIFTK-LINK-0003).
    /// Native boxes must answer an empty list while source-backed KParameter
    /// implementations keep their own `annotations` through interface
    /// dispatch.
    @Test
    func testKParameterAnnotationsMixRuntimeBoxesAndUserImplementations() throws {
        try compileAndRunKotlin(
            """
            import kotlin.reflect.KParameter
            import kotlin.reflect.KType

            class UserParam(override val index: Int, override val name: String) : KParameter {
                override val type: KType get() = throw UnsupportedOperationException()
                override val kind: KParameter.Kind get() = KParameter.Kind.VALUE
                override val isOptional: Boolean get() = false
                override val isVararg: Boolean get() = false
                override val annotations: List<Annotation> get() = listOf(object : Annotation {})
            }

            class C(val a: Int, val b: String)

            fun f(x: Int, y: String = "d") = Unit

            fun main() {
                for (p in ::f.parameters) {
                    println("${p.index}:${p.name}:${p.annotations.size}")
                }
                for (p in C::class.constructors.first().parameters) {
                    println("${p.index}:${p.name}:${p.annotations.size}")
                }
                val p: KParameter? = ::f.parameters.first()
                println(p?.annotations?.size)
                val u: KParameter = UserParam(0, "u")
                println(u.annotations.size)
            }
            """,
            expectedOutput: "0:x:0\n1:y:0\n0:a:0\n1:b:0\n0\n1\n",

    /// KUU-4068: `KType` extends `KAnnotatedElement`, but the bundled KType
    /// declaration omitted the supertype so `t.annotations` failed sema
    /// (KSWIFTK-SEMA-0024). With resolution restored, runtime KType boxes
    /// still have no `KAnnotatedElement` itable entry, so the read probes
    /// `__kk_ktype_is_runtime` and answers an empty list, while source-backed
    /// KType implementations keep their own `annotations` through interface
    /// dispatch.
    @Test
    func testKTypeAnnotationsMixRuntimeBoxesAndUserImplementations() throws {
        try compileAndRunKotlin(
            """
            import kotlin.reflect.KAnnotatedElement
            import kotlin.reflect.KClassifier
            import kotlin.reflect.KType
            import kotlin.reflect.KTypeProjection
            import kotlin.reflect.typeOf

            class UserType(
                override val classifier: KClassifier?,
                override val isMarkedNullable: Boolean
            ) : KType {
                override val arguments: List<KTypeProjection> get() = emptyList()
                override val annotations: List<Annotation>
                    get() = listOf(object : Annotation {}, object : Annotation {})
            }

            fun f(x: Int) = Unit

            fun describe(element: KAnnotatedElement): Int = element.annotations.size

            fun main() {
                val t = ::f.parameters.first().type
                println(t.annotations.size)
                println(typeOf<Int>().annotations.size)
                println(typeOf<List<String>>().annotations.size)
                println(::f.returnType.annotations.size)
                val u: KType = UserType(null, false)
                println(u.annotations.size)
                val tn: KType? = ::f.parameters.first().type
                println(tn?.annotations?.size)
                println(describe(t))
                println(describe(u))
            }
            """,
            expectedOutput: "0\n0\n0\n0\n2\n0\n0\n2\n",
            allowDefaultStdlibLibrary: false
        )
    }
}
#endif
