#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct ImportedInlineFunctionStoreTests {
    /// Import must not pay the artifact read + parse for every inline
    /// symbol up front: after `runToKIR` the store only holds descriptors,
    /// and the body is resolved the first time a caller asks for it.
    @Test func testImportRegistersDescriptorAndDefersParsing() throws {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir = baseDir.appendingPathExtension("kklib")
        let inlineDir = libDir.appendingPathComponent("inline-kir")
        try fm.createDirectory(at: inlineDir, withIntermediateDirectories: true)
        let t = defaultTargetTriple()
        let targetStr = "\(t.arch)-\(t.vendor)-\(t.os)"

        let manifest = """
        {
          "formatVersion": 1,
          "moduleName": "LazyInline",
          "kotlinLanguageVersion": "2.3.10",
          "target": "\(targetStr)",
          "metadata": "metadata.bin",
          "inlineKIRDir": "inline-kir"
        }
        """
        let metadata = """
        symbols=1
        function LazyBody fq=lib.foo schema=v1 arity=0 suspend=0 inline=1
        """
        let kirbin = """
        version=2
        params=0
        suspend=false
        body:
        beginBlock
        returnValue value=1
        """

        try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)
        try kirbin.write(to: inlineDir.appendingPathComponent("LazyBody.kirbin"), atomically: true, encoding: .utf8)

        try withTemporaryFile(contents: "fun main() = 0") { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "LazyInlineApp",
                emit: .kirDump,
                searchPaths: [libDir.path]
            )
            try runToKIR(ctx)

            let store = try #require(ctx.sema?.importedInlineFunctions)
            #expect(!store.isEmpty)
            #expect(store.descriptors.count == 1)
            // The regression this guards: import resolves the artifact path
            // but does not read or parse it.
            #expect(store.functions.isEmpty)

            let symbol = try #require(store.descriptors.keys.first)
            let arena = KIRArena()
            let resolved = try #require(store.function(for: symbol, arena: arena))
            #expect(!resolved.body.isEmpty)
            // Once resolved, the descriptor is consumed and the body is
            // cached — a second lookup reuses it without re-parsing.
            #expect(store.descriptors.isEmpty)
            #expect(store.functions[symbol]?.body.isEmpty == false)
            #expect(store.function(for: symbol, arena: arena) != nil)
            #expect(store.functions.count == 1)
        }
    }

    /// A descriptor whose artifact fails to parse drops out of the store,
    /// mirroring the eager path where a failed import left no table entry.
    @Test func testFailedParseRemovesDescriptor() throws {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir = baseDir.appendingPathExtension("kklib")
        let inlineDir = libDir.appendingPathComponent("inline-kir")
        try fm.createDirectory(at: inlineDir, withIntermediateDirectories: true)
        let t = defaultTargetTriple()
        let targetStr = "\(t.arch)-\(t.vendor)-\(t.os)"

        let manifest = """
        {
          "formatVersion": 1,
          "moduleName": "BadInline",
          "kotlinLanguageVersion": "2.3.10",
          "target": "\(targetStr)",
          "metadata": "metadata.bin",
          "inlineKIRDir": "inline-kir"
        }
        """
        let metadata = """
        symbols=1
        function BadBody fq=lib.foo schema=v1 arity=0 suspend=0 inline=1
        """
        let kirbin = """
        version=2
        params=0
        suspend=false
        body:
        beginBlock
        totallyUnknownOpcode result=1
        returnValue value=1
        """

        try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)
        try kirbin.write(to: inlineDir.appendingPathComponent("BadBody.kirbin"), atomically: true, encoding: .utf8)

        try withTemporaryFile(contents: "fun main() = 0") { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "BadInlineApp",
                emit: .kirDump,
                searchPaths: [libDir.path]
            )
            try runToKIR(ctx)

            let store = try #require(ctx.sema?.importedInlineFunctions)
            let symbol = try #require(store.descriptors.keys.first)
            let arena = KIRArena()
            #expect(store.function(for: symbol, arena: arena) == nil)
            // Failure matches the eager import outcome: no descriptor, no
            // function, and the symbol is recorded as failed rather than
            // retried on every call site.
            #expect(store.descriptors.isEmpty)
            #expect(store.functions.isEmpty)
            #expect(store.failedSymbols.contains(symbol))
            #expect(store.function(for: symbol, arena: arena) == nil)
        }
    }
}
#endif
