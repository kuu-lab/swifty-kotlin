#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

extension AnnotationSemanticTests {

    @Test func testNonRepeatableAnnotationCannotBeAppliedMoreThanOnce() {
        let ctx = runSemaCollectingDiagnostics(
            """
            annotation class Ann(val x: Int, val s: String = "d")

            @Ann(1) @Ann(2, "s")
            fun f() = 1

            @Repeatable
            annotation class Tag(val value: String)

            @Tag("first") @Tag("second")
            fun tagged() = 1
            """
        )

        let repeatabilityErrors = diagnostics(
            withCode: "KSWIFTK-SEMA-ANNOTATION-NOT-REPEATABLE",
            in: ctx
        )
        let errorLocations = repeatabilityErrors.prefix(12).compactMap { diagnostic -> String? in
            guard let range = diagnostic.primaryRange else { return nil }
            let file = range.start.file
            let data = ctx.sourceManager.contents(of: file)
            let start = max(0, range.start.offset - 24)
            let end = min(data.count, range.end.offset + 24)
            let source = String(decoding: data[start ..< end], as: UTF8.self)
                .replacingOccurrences(of: "\n", with: " ")
            let line = ctx.sourceManager.lineColumn(of: range.start).line
            return "\(ctx.sourceManager.path(of: file)):\(line): \(source)"
        }
        #expect(
            repeatabilityErrors.count == 1,
            "Expected one non-repeatable use error, got \(repeatabilityErrors.count): \(errorLocations)"
        )
        #expect(repeatabilityErrors.allSatisfy(isError))
    }
}
#endif
