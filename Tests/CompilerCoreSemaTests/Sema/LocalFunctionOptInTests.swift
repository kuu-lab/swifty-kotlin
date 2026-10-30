#if canImport(Testing)
@testable import CompilerCore
import Foundation
import TestStdlibCache
import Testing
@testable import CompilerTestSupport

@Suite
struct LocalFunctionOptInTests {
    @Test(arguments: [false, true])
    func bundledIoLocalExtensionsInheritOnlyEnclosingOptIn(usingKklib: Bool) throws {
        let source = """
        import kotlinx.io.*

        class BRC { suspend fun go() {} }

        @OptIn(InternalIoApi::class)
        private suspend fun BRC.outer() {
            fun Source.innerA(): Int = buffer.hashCode()
            suspend fun Source.innerB(): Int = buffer.hashCode()
        }

        @OptIn(InternalIoApi::class)
        private fun outer(src: Source): Int {
            fun inner(): Int = src.buffer.hashCode()
            return inner()
        }
        private suspend fun sibling(src: Source) {
            fun Source.unoptedA(): Int = buffer.hashCode()
            suspend fun Source.unoptedB(): Int = buffer.hashCode()
        }
        """
        let context = try semaContext(source, usingKklib: usingKklib)
        let diagnostics = userDiagnostics(in: context)
        let optInDiagnostics = diagnostics.filter { $0.code == "KSWIFTK-SEMA-OPT-IN" }
        #expect(optInDiagnostics.count == 2, "\(diagnostics)")
        let siblingStart = try #require(source.range(of: "private suspend fun sibling")).lowerBound
        let siblingOffset = source.utf8.distance(from: source.startIndex, to: siblingStart)
        #expect(optInDiagnostics.allSatisfy {
            $0.severity == .error && $0.message.contains("kotlinx.io.InternalIoApi")
                && ($0.primaryRange?.start.offset ?? -1) >= siblingOffset
        }, "Only the unopted sibling's local functions should require opt-in: \(diagnostics)")
        #expect(diagnostics.filter { $0.severity == .error }.count == 2, "\(diagnostics)")
    }

    @Test(arguments: ["@OptIn(LocalMarker::class)", "@LocalMarker"])
    func optInIsTransitiveThroughPlainAndExtensionLocalFunctions(annotation: String) throws {
        let source = """
        @RequiresOptIn
        annotation class LocalMarker
        interface Src { @LocalMarker val value: Int }

        \(annotation)
        fun Src.outer(src: Src): Int {
            fun middle(): Int {
                fun Src.leaf(): Int = value
                return src.leaf()
            }
            fun Src.extensionMiddle(): Int {
                fun Src.extensionLeaf(): Int = value
                return extensionLeaf()
            }
            return middle() + src.extensionMiddle()
        }
        """
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".kt").path
        let context = makeCompilationContext(inputs: [path], includeStdlib: false)
        _ = context.sourceManager.addFile(path: path, contents: Data(source.utf8))
        try runSema(context)
        #expect(userDiagnostics(in: context).filter { $0.severity == .error }.isEmpty,
                "\(context.diagnostics.diagnostics)")
    }

    private func semaContext(_ source: String, usingKklib: Bool) throws -> CompilationContext {
        if usingKklib {
            TestStdlibCache.shared.prepare()
            let artifactPath = try #require(CompilerOptions.defaultStdlibLibraryPath)
            #expect(FileManager.default.fileExists(atPath: artifactPath))
        }
        let context = makeContextFromSource(source, allowDefaultStdlibLibrary: usingKklib)
        try runSema(context)
        return context
    }

    private func userDiagnostics(in context: CompilationContext) -> [Diagnostic] {
        context.diagnostics.diagnostics.filter { diagnostic in
            diagnostic.primaryRange.map {
                context.sourceManager.origin(of: $0.start.file) == .user
            } == true
        }
    }
}
#endif
