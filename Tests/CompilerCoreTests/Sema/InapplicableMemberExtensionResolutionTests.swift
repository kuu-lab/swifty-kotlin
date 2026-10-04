#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct InapplicableMemberExtensionResolutionTests {
    @Test
    func qualifiedCallFallsBackToApplicableExtension() throws {
        let source = """
        class Box {
            fun append(a: Int, b: Int, c: Int): String = "member"
            fun score(value: Int): Int = value + 1
        }
        fun Box.append(value: Int): String = "extension"
        fun Box.score(value: String): Int = score(7)
        fun use(): Int {
            val box = Box()
            box.append(1)
            box.append(1, 2, 3)
            return box.score("x") + box.score(1)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "Expected member and extension overloads to coexist: \(ctx.diagnostics.diagnostics)")
        }
    }
}
#endif
