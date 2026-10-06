@testable import CompilerCore
import Testing

@Suite
struct PrimitiveBitFunctionTypeTests {

    // MARK: - Shared Sema context

    private static let sharedSources: [String] = [
        """
        package sample0
        fun probe(value: Long): Long {
            val takenHighest: Long = value.takeHighestOneBit()
            val takenLowest: Long = value.takeLowestOneBit()
            val bitCount: Int = value.countOneBits()
            return takenHighest + takenLowest + bitCount.toLong()
        }
        """,
        """
        package sample1
        fun probe(value: Long, scale: Double): Long {
            var accumulated = value
            accumulated -= 1L
            accumulated += 2L
            accumulated *= 3L
            var scaled = scale
            scaled /= 2.0
            return (accumulated and 0xFFL) + scaled.toLong()
        }
        """
    ]

    private static nonisolated(unsafe) var _sharedCtx: CompilationContext?

    private func sharedCtx() throws -> CompilationContext {
        if let cached = Self._sharedCtx { return cached }
        var result: CompilationContext?
        try withTemporaryFiles(contents: Self.sharedSources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)
            result = ctx
        }
        let ctx = try #require(result)
        Self._sharedCtx = ctx
        return ctx
    }
    @Test func testLongBitExtractionFunctionsPreserveLongResultType() throws {

        let ctx = try sharedCtx()
            #expect(
                ctx.diagnostics.diagnostics.isEmpty,
                Comment(rawValue: "Long bit functions should preserve their Kotlin result types, got: \(ctx.diagnostics.diagnostics)")
            )

    }

    /// BUG-015: an arithmetic compound assignment used to demote the target local to
    /// `Int`, so later `Long` member calls such as `value and 0xFFL` failed to resolve.
    @Test func testCompoundAssignmentPreservesNonIntNumericLocalTypes() throws {

        let ctx = try sharedCtx()
            #expect(
                ctx.diagnostics.diagnostics.isEmpty,
                Comment(rawValue: "Compound assignment should preserve Long/Double local types, got: \(ctx.diagnostics.diagnostics)")
            )

    }

    @Test
    func testUnsignedRotationsPreserveReceiverType() throws {
        let source = """
        fun probe(ui: UInt, ul: ULong, count: Int) {
            val leftUInt: UInt = ui.rotateLeft(count)
            val rightUInt: UInt = ui.rotateRight(count)
            val leftULong: ULong = ul.rotateLeft(count)
            val rightULong: ULong = ul.rotateRight(count)
            val safeUInt: UInt? = (ui as UInt?)?.rotateLeft(count)
            val safeULong: ULong? = (ul as ULong?)?.rotateRight(count)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
        }
    }

    @Test
    func testPhantomOneBitMembersAreRejected() throws {
        let source = """
        fun rejected(i: Int, l: Long) {
            i.highestOneBit()
            i.lowestOneBit()
            l.highestOneBit()
            l.lowestOneBit()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let errors = diagnosticsForPath(path, in: ctx).filter { $0.severity == .error }
            #expect(errors.count == 4)
            #expect(errors.allSatisfy { $0.code == "KSWIFTK-SEMA-0024" })
        }
    }

}
