#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// STDLIB-IO-FN-015: Validates that `File.copyTo(target, overwrite, bufferSize)`
/// resolves through Sema for the `java.io.File` receiver and produces a `File`.
///
/// The runtime link name exercised here is `kk_file_copyTo`.
///
/// Kotlin signature:
///
///     public fun File.copyTo(
///         target: File,
///         overwrite: Boolean = false,
///         bufferSize: Int = DEFAULT_BUFFER_SIZE
///     ): File
///
/// Declared in the `kotlin.io` package.
@Suite
struct FileCopyToFunctionTests {

    // MARK: - Shared Sema context

    private static let sharedSources: [String] = [
        """
        package sample0
        import java.io.File
        import kotlin.io.copyTo

        fun copy(source: File, dest: File): File = source.copyTo(dest)
        """,
        """
        package sample1
        import java.io.File
        import kotlin.io.copyTo

        fun copy(source: File, dest: File): File = source.copyTo(dest, true)
        """,
        """
        package sample2
        import java.io.File
        import kotlin.io.copyTo

        fun copy(source: File, dest: File): File = source.copyTo(dest, false, 8 * 1024)
        """,
        """
        package sample3
        import java.io.File
        import kotlin.io.copyTo

        fun copy(source: File, dest: File): File =
            source.copyTo(target = dest, bufferSize = 4096)
        """,
        """
        package sample4
        import java.io.File
        import kotlin.io.copyTo

        fun copy(source: File, dest: File): File = source.copyTo(dest, true, 4096)
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

    // MARK: - Single-argument overload (defaults for overwrite and bufferSize)

    @Test func testFileCopyToWithJustTargetResolves() throws {

        let ctx = try sharedCtx()
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected File.copyTo(target) to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    // MARK: - Two-argument overload (overwrite supplied)

    @Test func testFileCopyToWithOverwriteFlagResolves() throws {

        let ctx = try sharedCtx()
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected File.copyTo(target, overwrite) to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    // MARK: - Three-argument overload (all parameters supplied)

    @Test func testFileCopyToWithAllArgumentsResolves() throws {

        let ctx = try sharedCtx()
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected File.copyTo(target, overwrite, bufferSize) to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    // MARK: - Named arguments via default values

    @Test func testFileCopyToWithNamedBufferSizeResolves() throws {

        let ctx = try sharedCtx()
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected File.copyTo with named bufferSize to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    // MARK: - Sema surface inspection

    @Test func testFileCopyToExtensionFunctionSurfaceIsRegistered() throws {

        let ctx = try sharedCtx()
            #expect(
                !ctx.diagnostics.hasError,
                "File.copyTo extension function in kotlin.io should resolve: \(ctx.diagnostics.diagnostics.map(\.message))"
            )

            let interner = ctx.interner
            let sema = try #require(ctx.sema)
            let symbols = sema.symbols
            let types = sema.types

            let fileSymbol = try #require(
                symbols.lookup(fqName: ["java", "io", "File"].map(interner.intern))
            )
            let fileType = types.make(.classType(ClassType(
                classSymbol: fileSymbol, args: [], nullability: .nonNull
            )))

            let copyToCandidates = symbols.lookupAll(
                fqName: ["kotlin", "io", "copyTo"].map(interner.intern)
            )
            let copyTo = try #require(copyToCandidates.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID) else {
                    return false
                }
                return signature.receiverType == fileType
                    && signature.parameterTypes == [fileType, types.booleanType, types.intType]
                    && signature.returnType == fileType
            })

            #expect(
                symbols.externalLinkName(for: copyTo) == "kk_file_copyTo"
            )

            let signature = try #require(symbols.functionSignature(for: copyTo))
            #expect(signature.valueParameterHasDefaultValues == [false, true, true])
            #expect(signature.valueParameterIsVararg == [false, false, false])

    }
}
#endif
