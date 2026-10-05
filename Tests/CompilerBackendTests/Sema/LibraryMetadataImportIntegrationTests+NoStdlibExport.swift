#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension LibraryMetadataImportIntegrationTests {
    @Test(arguments: [false, true])
    func testUserLibraryExportsOnlyItsDeclarations(includeStdlib: Bool) throws {
        try withCompiledLibrary(
            source: "fun libraryValue(): Int = 42",
            moduleName: "ImportRepro",
            includeStdlib: includeStdlib,
            allowDefaultStdlibLibrary: includeStdlib
        ) { libraryPath in
            let data = try Data(contentsOf: URL(fileURLWithPath: libraryPath + "/metadata.bin"))
            let metadata = try #require(IndexedMetadataFile(data: data))
            #expect(metadata.entries.map(\.record.fqName) == ["libraryValue"])

            try assertImportedLibraryOutput(
                "fun main() { println(libraryValue()) }",
                searchPaths: [libraryPath],
                expected: "42\n"
            )
        }
    }

    @Test(arguments: [false, true])
    func testNoStdlibLibrariesKeepDistinctLazySignatures(reverseSearchPaths: Bool) throws {
        try withCompiledLibrary(
            source: "package left; fun libraryValue(): Int = 42",
            moduleName: "LeftLib",
            includeStdlib: false,
            allowDefaultStdlibLibrary: false
        ) { leftPath in
            try withCompiledLibrary(
                source: "package right; fun libraryValue(): String = \"library\"",
                moduleName: "RightLib",
                includeStdlib: false,
                allowDefaultStdlibLibrary: false
            ) { rightPath in
                let paths = reverseSearchPaths ? [rightPath, leftPath] : [leftPath, rightPath]
                let source = """
                import left.libraryValue as intValue
                import right.libraryValue as stringValue
                fun main() {
                    val number: Int = intValue()
                    val text: String = stringValue()
                    println(number)
                    println(text)
                }
                """
                try assertImportedLibraryOutput(source, searchPaths: paths, expected: "42\nlibrary\n") { ctx in
                    let sema = try #require(ctx.sema)
                    for (packageName, moduleName, returnType) in [
                        ("left", "LeftLib", sema.types.intType),
                        ("right", "RightLib", sema.types.stringType),
                    ] {
                        let candidates = sema.symbols.lookupAll(fqName: [
                            ctx.interner.intern(packageName), ctx.interner.intern("libraryValue"),
                        ])
                        #expect(candidates.count == 1)
                        let symbol = try #require(candidates.first)
                        #expect(sema.symbols.moduleFQN(for: symbol) == ctx.interner.intern(moduleName))
                        #expect(sema.symbols.functionSignature(for: symbol)?.returnType == returnType)
                    }
                }
            }
        }
    }

    @Test
    func testNoStdlibLibraryPreservesSourceBackedSyntheticMembers() throws {
        let source = """
        package userlib
        data class Box(val value: Int)
        enum class Choice { ONE }
        """
        try withCompiledLibrary(
            source: source,
            moduleName: "SyntheticMembers",
            includeStdlib: false,
            allowDefaultStdlibLibrary: false
        ) { libraryPath in
            let data = try Data(contentsOf: URL(fileURLWithPath: libraryPath + "/metadata.bin"))
            let metadata = try #require(IndexedMetadataFile(data: data))
            let names = Set(metadata.entries.map(\.record.fqName))
            #expect(names.contains("userlib.Box.component1"))
            #expect(names.contains("userlib.Box.copy"))
            #expect(names.contains("userlib.Choice.values"))
            #expect(!names.contains("kotlin.Any"))
            #expect(!names.contains("kotlin.collections.List"))

            try assertImportedLibraryOutput(
                """
                import userlib.*
                fun main() {
                    val (value) = Box(42)
                    println(value)
                    println(Choice.ONE.name)
                    println(Choice.values().size)
                }
                """,
                searchPaths: [libraryPath],
                expected: "42\nONE\n1\n"
            )
        }
    }

    private func assertImportedLibraryOutput(
        _ source: String,
        searchPaths: [String],
        expected: String,
        checkSema: (CompilationContext) throws -> Void = { _ in }
    ) throws {
        try withTemporaryFile(contents: source) { path in
            let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            defer { try? FileManager.default.removeItem(atPath: output) }
            let ctx = makeCompilationContext(
                inputs: [path], moduleName: "ImportApp", emit: .executable,
                outputPath: output, searchPaths: searchPaths
            )
            try runToKIR(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            try checkSema(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: output, arguments: [])
            #expect(result.exitCode == 0)
            #expect(result.stdout == expected)
        }
    }
}
#endif
