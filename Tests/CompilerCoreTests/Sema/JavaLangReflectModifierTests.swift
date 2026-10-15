@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

@Suite
struct JavaLangReflectModifierTests {
    @Test
    func modifierConstantsResolveFromBundledSourceStdlib() throws {
        let source = try diffCaseSource("java_reflect_modifier.kt", file: #filePath)
        let context = makeContextFromSource(source)

        try runSema(context)

        #expect(
            !context.diagnostics.hasError,
            "Modifier constants should resolve from the bundled source stdlib: \(context.diagnostics.diagnostics)"
        )
    }
}
