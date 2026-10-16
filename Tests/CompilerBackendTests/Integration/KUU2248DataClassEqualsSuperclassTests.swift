@testable import CompilerCore
import TestStdlibCache
import Testing

@Suite(.serialized)
struct KUU2248DataClassEqualsSuperclassTests {
    @Test(arguments: [false, true], [0, 2])
    func synthesizedEqualsIgnoresExplicitSuperclassEquals(
        useArtifact: Bool,
        optimization: Int
    ) throws {
        if useArtifact { TestStdlibCache.shared.prepare() }

        try compileAndRunKotlin(
            """
            // Regression based on Kotlin's nonTrivialMemberInSuperClass.kt.
            abstract class Base {
                override fun toString() = "Fail"
                override fun hashCode() = -42
                override fun equals(other: Any?) = false
            }
            data class DataClass(val field: String) : Base()

            fun originalRegression(): String {
                val value = DataClass("x")
                if (value.toString() != "DataClass(field=x)") return "Fail toString"
                if (value.hashCode() != "x".hashCode()) return "Fail hashCode"
                if (!value.equals(value)) return "Fail equals self"
                if (!value.equals(DataClass("x"))) return "Fail equals value"
                return "OK"
            }

            // Minimal reproducer: the base implementation must not veto property equality.
            open class FalseEqualsBase {
                override fun equals(other: Any?) = false
            }
            data class Child(val value: Int) : FalseEqualsBase()

            fun minimalRegression(): String =
                if (Child(1).equals(Child(1)) && Child(1) == Child(1)) "OK" else "FAIL"

            // Control case: inheriting Any.equals keeps the same data-class result.
            open class AnyEqualsBase
            data class Control(val value: Int) : AnyEqualsBase()

            fun inheritedAnyControl(): String =
                if (Control(1).equals(Control(1)) && Control(1) == Control(1)) "OK" else "FAIL"

            // A source-defined equals remains authoritative for its data class.
            data class ExplicitOverride(val value: Int) : FalseEqualsBase() {
                override fun equals(other: Any?): Boolean = other is ExplicitOverride && value == other.value
            }

            fun explicitOverrideControl(): String =
                if (ExplicitOverride(1) == ExplicitOverride(1)) "OK" else "FAIL"

            fun main() {
                println(originalRegression())
                println(minimalRegression())
                println(inheritedAnyControl())
                println(explicitOverrideControl())
            }
            """,
            expectedOutput: "OK\nOK\nOK\nOK\n",
            moduleName: "KUU2248DataClassEqualsSuperclass",
            allowDefaultStdlibLibrary: useArtifact,
            optLevel: try #require(OptimizationLevel(rawValue: optimization))
        )
    }
}
