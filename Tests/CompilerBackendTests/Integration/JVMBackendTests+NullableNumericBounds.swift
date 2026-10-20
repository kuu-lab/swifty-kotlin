#if canImport(Testing)
@testable import CompilerCore
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func nullableNumericBoundsUseNonNullEvidence(mode: EmitMode) throws {
        try assertJVM("""
        fun <T : Double?> asserted(v: T): Double = v!! * v!!
        fun <T : Double?> checked(v: T): Double = if (v != null) v * v else 0.0
        fun <T : Double?, U : T?> transitive(v: U): Double = v!! * v!!
        fun <T : Double?, U : T?> transitiveChecked(v: U): Double = if (v != null) v * v else 0.0
        fun main() {
            println(asserted(2.0)); println(checked(2.0)); println(checked<Double?>(null))
            try { println(asserted<Double?>(null)) } catch (e: NullPointerException) { println("null") }
            println(transitive<Double?, Double?>(2.0))
            try { println(transitive<Double?, Double?>(null)) } catch (e: NullPointerException) { println("null") }
            println(transitiveChecked<Double?, Double?>(2.0))
            println(transitiveChecked<Double?, Double?>(null))
        }
        """, "4.0\n4.0\n0.0\nnull\n4.0\nnull\n4.0\n0.0\n", mode: mode)
    }
}
#endif
