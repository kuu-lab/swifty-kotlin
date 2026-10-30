#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Foundation
import Testing
import TestStdlibCache

@Suite
struct ArrayListSubclassTests {
    private func makeContext(source: String, useArtifact: Bool) throws -> CompilationContext {
        let artifact: String?
        if useArtifact {
            TestStdlibCache.shared.prepare()
            artifact = try #require(CompilerOptions.defaultStdlibLibraryPath)
        } else {
            artifact = nil
        }
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".kt").path
        let ctx = makeCompilationContext(
            inputs: [path],
            includeStdlib: !useArtifact,
            stdlibLibraryPath: artifact,
            allowDefaultStdlibLibrary: false
        )
        _ = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8))
        return ctx
    }

    /// KUU-2666: `ArrayList` in bundled stdlib must be `open` (matching Kotlin/JVM)
    /// so user classes can inherit from it.
    @Test(arguments: [false, true])
    func arrayListCanBeSubclassed(useArtifact: Bool) throws {
        let source = """
        class Deck : ArrayList<String>()
        class CapacityDeck(cap: Int) : ArrayList<String>(cap)
        class CopyDeck(items: Collection<String>) : ArrayList<String>(items)

        open class BaseList : ArrayList<Int>() {
            override fun add(element: Int): Boolean {
                return super.add(element)
            }
        }

        class DerivedList : BaseList()
        """
        let ctx = try makeContext(source: source, useArtifact: useArtifact)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Unexpected diagnostics with useArtifact=\(useArtifact): \(errors)")
    }
}
#endif
