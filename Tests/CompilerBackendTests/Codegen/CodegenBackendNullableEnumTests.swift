#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Testing

@Suite
struct CodegenBackendNullableEnumTests {
    @Test
    func testNullableEnumNameOrdinal() throws {
        // Preserve the KUU-1970 verifier reproducer.
        let source = """
        enum class Mode { FAST, SLOW }
        fun getM(): Mode? = Mode.SLOW
        fun main() {
            val m = getM()
            println("${m?.name} ${m?.ordinal}")
        }
        """
        try assertKotlinOutput(source, moduleName: "NullableEnumNameOrdinal",
                               expected: "SLOW 1\n")
    }

    @Test
    func testNullableEnumMethods() throws {
        // Preserve the KUU-1970 runtime reproducer, including both unwrap forms.
        let source = """
        enum class Mode(val tag: Int) { FAST(1), SLOW(2);
            fun label() = "L$tag"
        }
        fun getM(): Mode? = Mode.SLOW
        fun main() {
            val m = getM()
            println(m?.label())
            if (m != null) println(m.label())
        }
        """
        try assertKotlinOutput(source, moduleName: "NullableEnumMethods",
                               expected: "L2\nL2\n")
    }

    @Test(arguments: [false, true], [true, false])
    func testNullableEnumUnwrapBoundaries(optimized: Bool, artifact: Bool) throws {
        let optLevel: OptimizationLevel = optimized ? .O2 : .O0
        let source = """
        enum class Mode(val tag: Int) {
            FAST(1), SLOW(2);
            fun label(suffix: String = "!") = "L$tag$suffix"
            fun num() = tag
        }
        enum class Action {
            FIRST { override fun label() = "first" },
            SECOND { override fun label() = "second" };
            abstract fun label(): String
        }
        class Plain { fun label() = "plain" }
        object Single { fun label() = "single" }
        fun getM(index: Int): Mode? = when (index) {
            0 -> Mode.FAST
            1 -> Mode.SLOW
            else -> null
        }
        fun getAction(): Action? = Action.SECOND
        fun Mode?.asAny(): Any? = this
        fun Any?.echo(): Any? = this
        fun suffix(): String { println("argument"); return "?" }
        fun show(m: Mode?) {
            println("${m?.name} ${m?.ordinal} ${m?.tag}")
            println(m?.label())
            println(m?.num())
            println(m?.asAny())
            println(m?.echo())
            if (m != null) {
                println("${m.name} ${m.ordinal} ${m.tag} ${m.label()}")
                println(m.asAny())
            }
        }
        fun main() {
            show(getM(0))
            show(getM(1))
            show(getM(2))
            println(getM(2)?.label(suffix()))
            val action = getAction()
            println(action?.label())
            if (action != null) println(action.label())
            println(Mode.FAST.label())
            println(Mode.SLOW.name)
            println(Mode.FAST.num())
            val plain: Plain? = Plain()
            println(plain?.label())
            val single: Single? = Single
            println(single?.label())
        }
        """
        try assertKotlinOutput(source, moduleName: "NullableEnumUnwrapBoundaries",
                               expected: """
                               FAST 0 1
                               L1!
                               1
                               FAST
                               FAST
                               FAST 0 1 L1!
                               FAST
                               SLOW 1 2
                               L2!
                               2
                               SLOW
                               SLOW
                               SLOW 1 2 L2!
                               SLOW
                               null null null
                               null
                               null
                               null
                               null
                               null
                               second
                               second
                               L1!
                               SLOW
                               1
                               plain
                               single
                               """ + "\n", optLevel: optLevel,
                               allowDefaultStdlibLibrary: artifact)
    }
}
#endif
