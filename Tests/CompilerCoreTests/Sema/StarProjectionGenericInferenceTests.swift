@testable import CompilerCore
import Foundation
import Testing

/// KSP-651: declaration-site variance projection must not swallow star projections,
/// otherwise `List<*>` / `Sequence<*>` arguments leave the callee's type variables
/// unconstrained and inference fails.
@Suite
struct StarProjectionGenericInferenceTests {
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
