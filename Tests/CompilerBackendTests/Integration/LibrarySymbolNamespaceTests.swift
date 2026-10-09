@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

@Suite(.serialized)
struct LibrarySymbolNamespaceTests {
    @Test
    func noStdlibProducersExportDistinctNativeLinkNames() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var linkNames: [String] = []
        for (packageName, returnType, value, module) in [
            ("left", "Int", "42", "LeftLib"),
            ("right", "String", "\"library\"", "RightLib"),
        ] {
            let sourcePath = directory.appendingPathComponent(module + ".kt").path
            let output = directory.appendingPathComponent(module).path
            try "package \(packageName)\nfun libraryValue(): \(returnType) = \(value)"
                .write(toFile: sourcePath, atomically: true, encoding: .utf8)
            let context = makeCompilationContext(
                inputs: [sourcePath], moduleName: module, emit: .library,
                outputPath: output, includeStdlib: false
            )
            try runToLowering(context)
            try assertNoDiagnosticErrors(context)
            try CodegenPhase().run(context)
            let metadata = try String(contentsOfFile: output + ".kklib/metadata.bin", encoding: .utf8)
            let record = try #require(MetadataDecoder().decode(metadata).first {
                $0.fqName == "\(packageName).libraryValue"
            })
            let linkName = try #require(record.externalLinkName)
            let kir = try #require(context.kir)
            let sema = try #require(context.sema)
            let functionSymbol = try #require(sema.symbols.lookup(fqName: [
                context.interner.intern(packageName), context.interner.intern("libraryValue"),
            ]))
            let function = try #require(findAllKIRFunctions(in: kir).first {
                $0.symbol == functionSymbol
            })
            #expect(linkName == CodegenSymbolSupport.cFunctionSymbol(
                for: function, interner: context.interner, moduleName: module,
                symbols: context.sema?.symbols
            ))
            linkNames.append(linkName)
        }
        #expect(linkNames[0] != linkNames[1])
    }

    @Test(arguments: [0, 2])
    func independentlyCompiledFunctionsLinkInBothSearchOrders(optimization: Int) throws {
        let level = try #require(OptimizationLevel(rawValue: optimization))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let stdlib = try testStdlibArtifactPath()

        func compile(source: String, module: String, emit: EmitMode, searchPaths: [String] = []) throws -> String {
            let sourcePath = directory.appendingPathComponent(module + ".kt").path
            let output = directory.appendingPathComponent(module).path
            try source.write(toFile: sourcePath, atomically: true, encoding: .utf8)
            let options = CompilerOptions(
                moduleName: module,
                inputs: [sourcePath],
                outputPath: output,
                emit: emit,
                searchPaths: searchPaths,
                target: defaultTargetTriple(),
                optLevel: level,
                stdlibLibraryPath: stdlib
            )
            try assertCompilationSucceeded(makeTestDriver().runForTesting(options: options), context: module)
            return emit == .library ? output + ".kklib" : output
        }

        let left = try compile(source: """
        package left
        fun libraryValue(): Int = 42
        inline fun inlineValue(): Int = libraryValue()
        val label: String get() = "left"
        """, module: "LeftLib", emit: .library)
        let right = try compile(source: """
        package right
        fun libraryValue(): String = "library"
        inline fun inlineValue(): String = libraryValue()
        val label: String get() = "right"
        """, module: "RightLib", emit: .library)

        for (index, paths) in [[left, right], [right, left]].enumerated() {
            let executable = try compile(source: """
            import left.libraryValue as leftValue
            import right.libraryValue as rightValue
            fun main() {
                println(leftValue())
                println(rightValue())
                println(left.inlineValue())
                println(right.inlineValue())
                println(left.label)
                println(right.label)
                val leftFunction = ::leftValue
                val rightFunction = ::rightValue
                println(leftFunction())
                println(rightFunction())
            }
            """, module: "Consumer\(index)", emit: .executable, searchPaths: paths)
            let result = try CommandRunner.run(executable: executable, arguments: [])
            #expect(result.exitCode == 0)
            #expect(result.stdout.replacingOccurrences(of: "\r\n", with: "\n") ==
                "42\nlibrary\n42\nlibrary\nleft\nright\n42\nlibrary\n")
        }
    }
}
