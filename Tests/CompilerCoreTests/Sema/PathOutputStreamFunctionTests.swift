#if canImport(Testing)
@testable import CompilerCore
import Testing

/// STDLIB-IO-PATH-FN-028: Validates that `kotlin.io.path.Path.outputStream(vararg options: OpenOption)`
/// resolves through Sema as an extension function on `java.nio.file.Path`.
/// The runtime link involved is `kk_path_outputStream`
/// (registered in `Sources/RuntimeABI/RuntimeABISpec.swift`).
@Suite
struct PathOutputStreamFunctionTests {

    // MARK: - Shared Sema context

    private static let sharedSources: [String] = [
        """
        package sample0
        import java.io.OutputStream
        import java.nio.file.OpenOption
        import java.nio.file.StandardOpenOption
        import kotlin.io.path.Path
        import kotlin.io.path.outputStream

        fun openSink(path: Path): OutputStream {
            return path.outputStream()
        }

        fun openSinkWithOption(path: Path, option: OpenOption): OutputStream {
            return path.outputStream(option)
        }

        fun openSinkWithStandardOptions(path: Path): OutputStream {
            return path.outputStream(StandardOpenOption.CREATE, StandardOpenOption.APPEND)
        }
        """,
        """
        package sample1
        fun noop() {}
        """
    ]

    private static nonisolated(unsafe) var _sharedCtx: CompilationContext?

    private func sharedCtx() throws -> CompilationContext {
        if let cached = Self._sharedCtx { return cached }
        var result: CompilationContext?
        try withTemporaryFiles(contents: Self.sharedSources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)
            result = ctx
        }
        let ctx = try #require(result)
        Self._sharedCtx = ctx
        return ctx
    }
    @Test func testPathOutputStreamResolvesInSource() throws {

        let ctx = try sharedCtx()
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected Path.outputStream(vararg options) to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    @Test func testPathOutputStreamResolvesToRuntimeLink() throws {

        let ctx = try sharedCtx()
            let interner = ctx.interner
            let sema = try #require(ctx.sema)
            let symbols = sema.symbols
            let types = sema.types
            let pathSymbol = try #require(symbols.lookup(fqName: ["kotlin", "io", "path", "Path"].map(interner.intern)))
            let openOptionSymbol = try #require(symbols.lookup(fqName: ["java", "nio", "file", "OpenOption"].map(interner.intern)))
            let outputStreamSymbol = try #require(symbols.lookup(fqName: ["java", "io", "OutputStream"].map(interner.intern)))
            let pathType = types.make(.classType(ClassType(classSymbol: pathSymbol, args: [], nullability: .nonNull)))
            let openOptionType = types.make(.classType(ClassType(classSymbol: openOptionSymbol, args: [], nullability: .nonNull)))
            let outputStreamType = types.make(.classType(ClassType(classSymbol: outputStreamSymbol, args: [], nullability: .nonNull)))

            let outputStreamSymbols = symbols.lookupAll(fqName: ["kotlin", "io", "path", "outputStream"].map(interner.intern))
            let outputStream = try #require(outputStreamSymbols.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID) else { return false }
                return signature.receiverType == pathType
                    && signature.parameterTypes == [openOptionType]
                    && signature.returnType == outputStreamType
            })

            #expect(symbols.externalLinkName(for: outputStream) == "kk_path_outputStream")

            let signature = try #require(symbols.functionSignature(for: outputStream))
            #expect(signature.valueParameterHasDefaultValues == [false])
            #expect(signature.valueParameterIsVararg == [true])

    }
}
#endif
