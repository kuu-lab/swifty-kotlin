#if canImport(Testing)
@testable import CompilerBackend
@testable import CompilerCore
import Foundation
import Testing

/// Callers of an erased `T` parameter box primitives, so vtable/itable bridges
/// must unbox them before forwarding to an override that declares the raw
/// primitive (otherwise e.g. `Double` arithmetic ran on box-pointer bits).
@Suite
struct CodegenBackendErasedBridgePrimitiveParamTests {
    @Test
    func testVtableBridgeUnboxesDoubleFloatCharBooleanParams() throws {
        let source = """
        abstract class Acc<T> { abstract fun add(a: T, b: T): T; fun sumAll(xs: List<T>, zero: T): T { var acc = zero; for (x in xs) acc = add(acc, x); return acc } }
        class DblAcc : Acc<Double>() { override fun add(a: Double, b: Double) = a + b }
        class FltAcc : Acc<Float>() { override fun add(a: Float, b: Float) = a + b }
        class ChrAcc : Acc<Char>() { override fun add(a: Char, b: Char) = if (a > b) a else b }
        class BoolAcc : Acc<Boolean>() { override fun add(a: Boolean, b: Boolean) = a || b }
        fun main() {
            println(DblAcc().sumAll(listOf(0.5, 0.25), 0.0))
            println(FltAcc().sumAll(listOf(0.5f, 0.25f), 0.0f))
            println(ChrAcc().sumAll(listOf('a', 'z', 'c'), 'a'))
            println(BoolAcc().sumAll(listOf(false, true), false))
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "VtableBridgeUnboxParams",
            expected: "0.75\n0.75\nz\ntrue\n"
        )
    }

    @Test
    func testItableBridgeUnboxesParamsIncludingUnitReturn() throws {
        let source = """
        interface Op<T> { fun combine(a: T, b: T): T }
        object DblOp : Op<Double> { override fun combine(a: Double, b: Double) = a * b }
        interface Sink<T> { fun accept(x: T) }
        class DblSink : Sink<Double> { var total = 0.0; override fun accept(x: Double) { total += x } }
        class BoolSink : Sink<Boolean> { var v = false; override fun accept(x: Boolean) { v = x } }
        fun <T> fold(xs: List<T>, z: T, op: Op<T>): T { var acc = z; for (x in xs) acc = op.combine(acc, x); return acc }
        fun main() {
            val op: Op<Double> = DblOp
            println(op.combine(1.5, 2.0))
            println(fold(listOf(2.0, 3.0), 1.0, DblOp))
            val s: Sink<Double> = DblSink(); s.accept(1.5); s.accept(2.0)
            println((s as DblSink).total)
            val b: Sink<Boolean> = BoolSink(); b.accept(true)
            println((b as BoolSink).v)
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "ItableBridgeUnboxParams",
            expected: "3.0\n6.0\n3.5\ntrue\n"
        )
    }
}
#endif
