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

    @Test func userCallableImplementationsKeepSourceDispatch() throws {
        try compileAndRunKotlin(
            """
            import kotlin.reflect.KCallable
            import kotlin.reflect.KParameter
            import kotlin.reflect.KTypeParameter
            import kotlin.reflect.KVisibility
            import kotlin.reflect.typeOf

            class UserCallable : KCallable<Int> {
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
            }
            """,
            expectedOutput: "99\n98\nuser\n0\ntrue\nPRIVATE\n",
            moduleName: "CallableSourceDispatch"
        )
    }
}
