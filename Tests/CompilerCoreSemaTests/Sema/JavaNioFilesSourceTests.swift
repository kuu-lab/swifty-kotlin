@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct JavaNioFilesSourceTests {
    @Test
    func testPublicFacadeResolvesFromBundledSource() throws {
        let context = makeContextFromSource("""
        import java.nio.file.Files
        import java.nio.file.Path
        import java.nio.file.Paths
        fun path(): Path = Paths.get("parts", "input.txt")
        fun bytes(path: Path): ByteArray = Files.readAllBytes(path)
        """)
        try runSema(context)
        #expect(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
        let sema = try #require(context.sema)
        for name in ["Path", "Paths", "Files"] {
            let symbol = try #require(sema.symbols.lookup(
                fqName: ["java", "nio", "file", name].map { context.interner.intern($0) }
            ))
            #expect(sema.symbols.isSourceBackedSymbol(symbol))
        }
    }

    @Test(arguments: [
        "Files.readAllBytes(\"input.txt\")",
        "Paths.get(42)",
        "Files.readString(Paths.get(\"input.txt\"))",
    ])
    func testFacadeRejectsWrongTypesAndUnsupportedMembers(expression: String) throws {
        let context = makeContextFromSource("""
        import java.nio.file.Files
        import java.nio.file.Paths
        fun main() { println(\(expression)) }
        """)
        do {
            try runSema(context)
        } catch {
            // The diagnostic, rather than the pipeline error, owns rejection.
        }
        #expect(context.diagnostics.hasError, "Expected rejection of \(expression)")
    }
}
