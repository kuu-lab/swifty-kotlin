#if canImport(Testing)
@testable import CompilerCore
import Testing

/// Operator-syntax calls on an open/abstract member operator must lower to a
/// `.virtualCall` (like `lhs.plus(rhs)` does), not a direct `.call` to the
/// statically chosen declaration. Covers binary operators, comparison
/// (`compareTo`) and equality (`equals`) desugaring, `in`, and
/// declaration / for-loop destructuring.
extension BuildKIRRegressionTests {
    @Test
    func binaryOperatorOnBaseTypedReceiverDispatchesVirtually() throws {
        let source = """
        abstract class Shape { abstract operator fun plus(n: Int): Int }
        class Sq(val s: Int) : Shape() { override operator fun plus(n: Int) = s * s + n }
        open class A(val v: Int) : Comparable<A> { override fun compareTo(other: A): Int = v - other.v }
        class B(v: Int) : A(v) { override fun compareTo(other: A): Int = other.v - v }
        open class E { override fun equals(other: Any?) = false; override fun hashCode() = 1 }
        class F : E() { override fun equals(other: Any?) = true; override fun hashCode() = 0 }
        fun plusProbe(x: Shape): Int = x + 1
        fun compareProbe(x: A): Boolean = x < A(2)
        fun equalsProbe(x: E): Boolean = x == E()
        """
        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)
        let module = try #require(ctx.kir)

        for (probe, callee) in [("plusProbe", "plus"), ("compareProbe", "compareTo"), ("equalsProbe", "equals")] {
            let body = try findKIRFunctionBody(named: probe, in: module, interner: ctx.interner)
            let virtualCallees = extractVirtualCallees(from: body, interner: ctx.interner)
            #expect(virtualCallees.contains(callee), "\(probe): expected virtual \(callee), got virtual \(virtualCallees), direct \(extractCallees(from: body, interner: ctx.interner))")
        }
    }

    @Test
    func containsOperatorOnBaseTypedReceiverDispatchesVirtually() throws {
        let source = """
        open class Bag { open operator fun contains(x: Int): Boolean = false }
        class EvenBag : Bag() { override fun contains(x: Int): Boolean = x % 2 == 0 }
        fun inProbe(c: Bag): Boolean = 4 in c
        fun notInProbe(c: Bag): Boolean = 3 !in c
        """
        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)
        let module = try #require(ctx.kir)

        for probe in ["inProbe", "notInProbe"] {
            let body = try findKIRFunctionBody(named: probe, in: module, interner: ctx.interner)
            let virtualCallees = extractVirtualCallees(from: body, interner: ctx.interner)
            #expect(virtualCallees.contains("contains"), "\(probe): got virtual \(virtualCallees), direct \(extractCallees(from: body, interner: ctx.interner))")
        }
    }

    @Test
    func destructuringOverriddenComponentsDispatchesVirtually() throws {
        let source = """
        open class P(val a: Int, val b: Int) { open operator fun component1() = a; open operator fun component2() = b }
        class Q(a: Int, b: Int) : P(a, b) { override fun component1() = a * 10; override fun component2() = b * 10 }
        fun declProbe(p: P): Int { val (x, y) = p; return x + y }
        fun loopProbe(ps: List<P>): Int { var s = 0; for ((x, y) in ps) s += x + y; return s }
        """
        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)
        let module = try #require(ctx.kir)

        for probe in ["declProbe", "loopProbe"] {
            let body = try findKIRFunctionBody(named: probe, in: module, interner: ctx.interner)
            let virtualCallees = extractVirtualCallees(from: body, interner: ctx.interner)
            #expect(virtualCallees.contains("component1"), "\(probe): got virtual \(virtualCallees)")
            #expect(virtualCallees.contains("component2"), "\(probe): got virtual \(virtualCallees)")
        }
    }
}
#endif
