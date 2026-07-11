#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct LibraryMetadataSignatureParsingTests {

    @Test func testDeeplyNestedNullableSignatureDoesNotCrashAndEmitsWarning() throws {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir = baseDir.appendingPathExtension("kklib")
        try fm.createDirectory(at: libDir, withIntermediateDirectories: true)

        let nesting = 1000
        let prefix = String(repeating: "Q<", count: nesting)
        let suffix = String(repeating: ">", count: nesting)
        let sig = prefix + "I" + suffix

        let manifest = """
        {
          "formatVersion": 1,
          "moduleName": "DeepNest",
          "metadata": "metadata.bin"
        }
        """
        let metadata = "symbols=1\nproperty _ fq=deepnest.x schema=v1 sig=\(sig)\n"
        try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)

        try withTemporaryFile(contents: "fun main() = 0") { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "DeepNestApp",
                emit: .kirDump,
                searchPaths: [libDir.path]
            )
            let symbols = SymbolTable()
            let types = TypeSystem()
            let diagnostics = DiagnosticEngine()
            let interner = StringInterner()
            var inlineFns: [SymbolID: KIRFunction] = [:]

            DataFlowSemaPhase().loadImportedLibrarySymbols(
                options: ctx.options,
                symbols: symbols,
                types: types,
                diagnostics: diagnostics,
                interner: interner,
                importedInlineFunctions: &inlineFns
            )

            let warnings = diagnostics.diagnostics.filter { $0.code == "KSWIFTK-LIB-0003" }
            #expect(warnings.count == 1, "Expected a single malformed-signature warning for recursion depth, got: \(diagnostics.diagnostics.map(\.code))")
            let xSymbol = symbols.allSymbols().first { symbol in
                interner.resolve(symbol.name) == "x" && symbol.kind == .property
            }
            #expect(xSymbol != nil, "Property symbol should still be imported despite the malformed signature")
        }
    }

    @Test func testDeeplyNestedValueClassUnderlyingSignatureDoesNotCrashAndEmitsWarning() throws {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir = baseDir.appendingPathExtension("kklib")
        try fm.createDirectory(at: libDir, withIntermediateDirectories: true)

        let nesting = 1000
        let prefix = String(repeating: "Q<", count: nesting)
        let suffix = String(repeating: ">", count: nesting)
        let sig = prefix + "I" + suffix

        let manifest = """
        {
          "formatVersion": 1,
          "moduleName": "ValueClassDeepNest",
          "metadata": "metadata.bin"
        }
        """
        let metadata = "symbols=1\nclass _ fq=vc.deep schema=v1 valueClass=1 valueUnderlying=\(sig)\n"
        try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)

        try withTemporaryFile(contents: "fun main() = 0") { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "ValueClassDeepNestApp",
                emit: .kirDump,
                searchPaths: [libDir.path]
            )
            let symbols = SymbolTable()
            let types = TypeSystem()
            let diagnostics = DiagnosticEngine()
            let interner = StringInterner()
            var inlineFns: [SymbolID: KIRFunction] = [:]

            DataFlowSemaPhase().loadImportedLibrarySymbols(
                options: ctx.options,
                symbols: symbols,
                types: types,
                diagnostics: diagnostics,
                interner: interner,
                importedInlineFunctions: &inlineFns
            )

            let warnings = diagnostics.diagnostics.filter { $0.code == "KSWIFTK-LIB-0003" }
            #expect(warnings.count == 1, "Expected a single malformed-signature warning for value class underlying recursion depth, got: \(diagnostics.diagnostics.map(\.code))")
        }
    }

    @Test func testSignatureAtDepthLimitParsesWithoutWarning() throws {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir = baseDir.appendingPathExtension("kklib")
        try fm.createDirectory(at: libDir, withIntermediateDirectories: true)

        let nesting = 500
        let prefix = String(repeating: "Q<", count: nesting)
        let suffix = String(repeating: ">", count: nesting)
        let sig = prefix + "I" + suffix

        let manifest = """
        {
          "formatVersion": 1,
          "moduleName": "AtDepthLimit",
          "metadata": "metadata.bin"
        }
        """
        let metadata = "symbols=1\nproperty _ fq=atdepth.x schema=v1 sig=\(sig)\n"
        try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)

        try withTemporaryFile(contents: "fun main() = 0") { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "AtDepthLimitApp",
                emit: .kirDump,
                searchPaths: [libDir.path]
            )
            let symbols = SymbolTable()
            let types = TypeSystem()
            let diagnostics = DiagnosticEngine()
            let interner = StringInterner()
            var inlineFns: [SymbolID: KIRFunction] = [:]

            DataFlowSemaPhase().loadImportedLibrarySymbols(
                options: ctx.options,
                symbols: symbols,
                types: types,
                diagnostics: diagnostics,
                interner: interner,
                importedInlineFunctions: &inlineFns
            )

            let warnings = diagnostics.diagnostics.filter { $0.code == "KSWIFTK-LIB-0003" }
            #expect(warnings.isEmpty, "Expected a 500-deep nullable signature to parse within the depth limit: \(diagnostics.diagnostics.map(\.code))")
            let xSymbol = symbols.allSymbols().first { symbol in
                interner.resolve(symbol.name) == "x" && symbol.kind == .property
            }
            #expect(xSymbol != nil, "Property 'x' should be imported")
        }
    }
}
#endif
