#if canImport(Testing)
@testable import CompilerBackend
@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

@Suite(.serialized)
struct ExpectActualObjectPropertyExecutionTests {
    @Test(arguments: [0, 2])
    func actualObjectMemberPropertiesUseActualDeclarations(optimization: Int) throws {
        try compileAndRunKotlinSources(
            [
                """
                package x
                expect abstract class B
                expect object Reg {
                    val A: B
                    val C: B
                    val NumberA: Int
                    val NumberC: Int
                    val StoredA: B
                    val StoredC: B
                }
                """,
                """
                package x
                actual abstract class B
                private val PA: B = object : B() {}
                private val PC: B = object : B() {}
                actual object Reg {
                    actual val A: B get() {
                        println("GETTER_A")
                        return PA
                    }
                    actual val C: B get() {
                        println("GETTER_C")
                        return PC
                    }
                    actual val NumberA: Int = 11
                    actual val NumberC: Int = 22
                    actual val StoredA: B = PA
                    actual val StoredC: B = PC
                }
                fun main() {
                    println(PA === PC)
                    println(Reg.NumberA)
                    println(Reg.NumberC)
                    println(Reg.StoredA === Reg.StoredC)
                    println(Reg.A === Reg.C)
                    println(Reg.A === PA)
                    println(Reg.A === Reg.A)
                }
                """,
            ],
            expectedOutput: """
            false
            11
            22
            false
            GETTER_A
            GETTER_C
            false
            GETTER_A
            true
            GETTER_A
            GETTER_A
            true

            """,
            moduleName: "ExpectActualObjectProperty",
            allowDefaultStdlibLibrary: true,
            optLevel: try #require(OptimizationLevel(rawValue: optimization))
        )
    }
}
#endif
