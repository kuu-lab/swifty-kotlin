import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [false, true])
    func inheritedListPropertyReferenceReadsSize(fromArtifact: Bool) throws {
        try compileAndRunKotlin(
            """
            fun main() {
                val size = List<Int>::size
                println(size.get(listOf(1, 2)))
                println(size.get(emptyList<Int>()))
                val mutableSize = MutableList<Int>::size
                println(mutableSize.get(mutableListOf(1, 2, 3)))
            }
            """,
            expectedOutput: "2\n0\n3\n",
            moduleName: "InheritedListPropertyReference",
            allowDefaultStdlibLibrary: fromArtifact
        )
    }

    @Test func inheritedGenericPropertyReferenceReadsStoredValue() throws {
        try compileAndRunKotlin(
            """
            open class Parent<T>(val value: T)
            class Child<T>(value: T) : Parent<T>(value)
            fun main() {
                val ref = Child<Int>::value
                println(ref.get(Child(42)))
            }
            """,
            expectedOutput: "42\n",
            moduleName: "InheritedGenericPropertyReference"
        )
    }

    @Test(arguments: [true, false])
    func functionReferenceNameAndCall(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            """
            fun topFn(a: Int) = a + 1
            fun main() {
                val f = ::topFn
                println(f.name)
                println(f.call(3))
                println(f(3))
                println(f.invoke(3))
            }
            """,
            expectedOutput: "topFn\n4\n4\n4\n",
            moduleName: "KUU1231FunctionReference",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }

    @Test(arguments: [true, false])
    func varargKParameterTypesUseCorrespondingArrayTypes(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            """
            import kotlin.reflect.*

            fun sum(vararg values: Long): Long = values.sum()
            fun collect(vararg values: String): Int = values.size

            fun main() {
                val primitive = ::sum.parameters.single()
                val reference = ::collect.parameters.single()
                println("${primitive.name}:${primitive.type}:${primitive.isVararg}")
                println("${reference.name}:${reference.type}:${reference.isVararg}")
            }
            """,
            expectedOutput: "values:kotlin.LongArray:true\nvalues:kotlin.Array<out kotlin.String>:true\n",
            moduleName: "KUU1444VarargKParameterTypes",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }

    @Test func callableReferencesExposeGenericTypeParameters() throws {
        try compileAndRunKotlin(
            """
            fun <T> identity(value: T): T = value
            fun main() {
                val ref = ::identity
                println(ref.typeParameters.size)
                println(ref.typeParameters[0].name)
                println(ref.typeParameters[0].upperBounds.size)
                println(ref.typeParameters[0].variance)
                println(ref.typeParameters[0].isReified)
            }
            """,
            expectedOutput: "1\nT\n1\nINVARIANT\nfalse\n",
            moduleName: "CallableTypeParameters"
        )
    }

    @Test(arguments: [true, false])
    func functionReferenceCallableMembers(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            """
            import kotlin.reflect.KCallable
            fun add(a: Int, b: Int) = a + b
            private fun hidden() = 1
            suspend fun suspended() = 2
            fun main() {
                val r = ::add
                println(r.parameters.size)
                println(r.callBy(mapOf(r.parameters[0] to 1, r.parameters[1] to 2)))
                println(r.returnType)
                println(r.isSuspend)
                println(r.annotations)
                println(r.visibility)
                val callable: KCallable<Int> = r
                println(callable.parameters.size)
                println(callable.callBy(mapOf(callable.parameters[1] to 4, callable.parameters[0] to 3)))
                println(callable.returnType)
                println(callable.isSuspend)
                println(callable.annotations)
                println(callable.visibility)
                println(::hidden.visibility)
                println(::suspended.isSuspend)
            }
            """,
            expectedOutput: "2\n3\nkotlin.Int\nfalse\n[]\nPUBLIC\n2\n7\nkotlin.Int\nfalse\n[]\nPUBLIC\nPRIVATE\ntrue\n",
            moduleName: "KUU1309CallableMembers",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }

    @Test(arguments: [true, false])
    func functionReferenceAnnotations(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            """
            import kotlin.reflect.KCallable
            import kotlin.annotation.Retention as Keep
            import kotlin.annotation.AnnotationRetention.SOURCE as SourceRetention
            annotation class Marker
            @Keep(value = SourceRetention) annotation class SourceMarker
            @kotlin.annotation.Retention(AnnotationRetention.BINARY) annotation class BinaryMarker
            @Keep(AnnotationRetention.RUNTIME) annotation class RuntimeMarker
            @Marker @SourceMarker @BinaryMarker @RuntimeMarker fun marked() = 1
            fun plain() = 2
            fun main() {
                val ref = ::marked
                println(ref.annotations.size)
                println(ref.annotations.size)
                val callable: KCallable<Int> = ref
                println(callable.annotations.size)
                println(::marked.annotations.size)
                println(::plain.annotations.size)
            }
            """,
            expectedOutput: "2\n2\n2\n2\n0\n",
            moduleName: "KUU1309CallableAnnotations",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }

    @Test func userCallableImplementationsKeepSourceDispatch() throws {
        try compileAndRunKotlin(
            """
            import kotlin.reflect.KCallable
            import kotlin.reflect.KParameter
            import kotlin.reflect.KTypeParameter
            import kotlin.reflect.KVisibility
            import kotlin.reflect.typeOf

            class UserCallable : KCallable<Int> {
                override val annotations: List<Annotation>
                    get() = throw IllegalStateException("user annotations")
                override val name = "user"
                override val parameters = emptyList<KParameter>()
                override val returnType = typeOf<Int>()
                override val typeParameters = emptyList<KTypeParameter>()
                override val visibility = KVisibility.PRIVATE
                override val isFinal = false
                override val isOpen = true
                override val isAbstract = false
                override val isSuspend = false
                override fun call(vararg args: Any?) = 99
                override fun callBy(args: Map<KParameter, Any?>) = 98
            }

            fun main() {
                val callable: KCallable<Int> = UserCallable()
                println(callable.call(1))
                println(callable.callBy(emptyMap()))
                println(callable.name)
                println(callable.parameters.size)
                println(callable.isOpen)
                println(callable.visibility)
                try { callable.annotations } catch (e: IllegalStateException) { println(e.message) }
            }
            """,
            expectedOutput: "99\n98\nuser\n0\ntrue\nPRIVATE\nuser annotations\n",
            moduleName: "CallableSourceDispatch"
        )
    }
}
