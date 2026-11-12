#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

@Suite
struct JVMCharTitlecaseTests {

    @Test
    func charTitlecaseReturnsStringAndRejectsStringReceiver() throws {
        let context = makeContextFromSource(
            """
            fun asciiTitlecase(): String = 'a'.titlecase()
            fun expandedTitlecase(): String = 'ß'.titlecase()
            fun stringTitlecase(): String = "a".titlecase()
            """,
            emit: .jvmJar
        )
        try JVMPreparationPhase().run(context)
        try runSema(context)

        let errors = context.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.count == 1, "Expected only String.titlecase() to be rejected: \(errors)")
        #expect(errors.first?.code == "KSWIFTK-SEMA-0024")
        #expect(errors.first?.message.contains("titlecase") == true)
    }
}
#endif
