@testable import CompilerCore
import Testing

@Suite
struct MutableMapJava8DefaultMethodsTests {
    @Test
    func java8DefaultMethodsResolveFromSource() throws {
        let source = try diffCaseSource("kuu_3123_mutable_map_java8_defaults.kt", file: #filePath)
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                emit: .kirDump,
                allowDefaultStdlibLibrary: false
            )
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        }
    }
}
