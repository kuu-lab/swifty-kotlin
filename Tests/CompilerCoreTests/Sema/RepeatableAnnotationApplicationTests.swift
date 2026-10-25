#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct RepeatableAnnotationApplicationTests {
    @Test
    func rejectsRepeatedNonRepeatableAnnotationAndAcceptsRepeatableOne() throws {
        let ctx = makeContextFromSource(
            """
            @Target(AnnotationTarget.CLASS)
            annotation class SingleUse

            @SingleUse
            @SingleUse
            class Duplicate

            @Target(AnnotationTarget.CLASS)
            @Repeatable
            annotation class RepeatedUse

            @RepeatedUse
            @RepeatedUse
            class Allowed
            """
        )
        try runSema(ctx)

        let repeatedAnnotationErrors = ctx.diagnostics.diagnostics.filter {
            $0.code == "KSWIFTK-SEMA-ANNOTATION-REPEATED"
        }
        #expect(repeatedAnnotationErrors.count == 1, "\(ctx.diagnostics.diagnostics)")
        #expect(repeatedAnnotationErrors.first?.severity == .error)
        #expect(repeatedAnnotationErrors.first?.message == "Annotation '@SingleUse' is not repeatable.")
        #expect(
            !ctx.diagnostics.diagnostics.contains {
                $0.severity == .error && $0.code != "KSWIFTK-SEMA-ANNOTATION-REPEATED"
            },
            "\(ctx.diagnostics.diagnostics)"
        )
    }
}
#endif
