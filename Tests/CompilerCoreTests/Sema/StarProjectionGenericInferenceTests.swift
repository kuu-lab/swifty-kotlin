@testable import CompilerCore
import Foundation
import Testing

/// KSP-651: declaration-site variance projection must not swallow star projections,
/// otherwise `List<*>` / `Sequence<*>` arguments leave the callee's type variables
/// unconstrained and inference fails.
@Suite
struct StarProjectionGenericInferenceTests {
    @Test
    func testStarProjectedFBoundedMemberRemainsCallable() throws {
        let ctx = makeContextFromSource("""
        interface Copyable<T> where T : Throwable, T : Copyable<T> {
            fun copy(): T?
            fun <U : Number> checked(value: U): U
        }
        fun copy(value: Copyable<*>): Throwable? = value.copy()
        fun checked(value: Copyable<*>): Int = value.checked(7)
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.diagnostics.filter { $0.severity == .error }.isEmpty)
    }

    @Test
    func testStarProjectedReceiverStillChecksMethodTypeParameterBounds() throws {
        let ctx = makeContextFromSource("""
        interface Copyable<T> where T : Throwable, T : Copyable<T> {
            fun <U : Number> checked(value: U): U
        }
        fun invalid(value: Copyable<*>) = value.checked<String>("wrong")
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.diagnostics.contains {
            $0.severity == .error && $0.code == "KSWIFTK-SEMA-BOUND"
        })
    }

    @Test
    func testStarProjectedFBoundDoesNotAcceptAnUpperBoundAsInput() throws {
        for member in ["fun accept(value: T)", "fun <U : T> accept(value: U)"] {
            let ctx = makeContextFromSource("""
            interface Copyable<T> where T : Throwable, T : Copyable<T> {
                \(member)
            }
            fun invalid(value: Copyable<*>) = value.accept(Exception())
            """)
            try runSema(ctx)
            #expect(ctx.diagnostics.hasError)
        }
    }

    @Test
    func testStarProjectionArgumentConstrainsCalleeTypeVariable() throws {
        let source = """
        fun <T> firstOrDef(xs: List<T>): T? = xs.firstOrNull()

        fun <T> sizeOf(xs: Collection<T>): Int = xs.size

        fun <T> countSeq(s: Sequence<T>): Int = s.count()

        fun useStarList(xs: List<*>): String {
            val first = firstOrDef(xs)
            val size = sizeOf(xs)
            return "$first $size"
        }

        fun useStarSequence(s: Sequence<*>): Int = countSeq(s)
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            assertNoDiagnostic("KSWIFTK-SEMA-INFER", in: ctx)
            assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
        }
    }
}
