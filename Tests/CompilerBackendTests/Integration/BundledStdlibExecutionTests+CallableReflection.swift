import Testing

extension BundledStdlibExecutionTests {
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
