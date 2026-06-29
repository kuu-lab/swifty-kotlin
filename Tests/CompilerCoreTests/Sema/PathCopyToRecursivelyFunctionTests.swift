#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// STDLIB-IO-PATH-FN-010: Validates that `kotlin.io.path.Path.copyToRecursively(...)` resolves
/// through Sema for both overload shapes:
///   - `copyToRecursively(target, onError, followLinks, overwrite): Path`  → kk_path_copyToRecursively_overwrite
///   - `copyToRecursively(target, onError, followLinks, copyAction): Path` → kk_path_copyToRecursively_copyAction
///
/// The extension functions are wired through the synthetic Path stub registry in
/// `Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+SyntheticPathStubs.swift`, and are
/// expected to bind to the runtime helpers declared in
/// `Sources/RuntimeABI/RuntimeABISpec.swift`.
@Suite
struct PathCopyToRecursivelyFunctionTests {
    // MARK: - overwrite overload

    @Test func testPathCopyToRecursivelyOverwriteResolvesWithAllArguments() throws {
        let source = """
        import kotlin.Exception
        import kotlin.io.path.OnErrorResult
        import kotlin.io.path.Path
        import kotlin.io.path.copyToRecursively

        fun copyTree(source: Path, target: Path, onError: (Path, Path, Exception) -> OnErrorResult): Path {
            return source.copyToRecursively(target, onError, true, true)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(
                errors.isEmpty,
                "Path.copyToRecursively(target, onError, followLinks, overwrite) should resolve without errors, got: \(errors.map { "\($0.code): \($0.message)" })"
            )
        }
    }

    @Test func testPathCopyToRecursivelyOverwriteSignatureAndRuntimeLink() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let interner = ctx.interner
            let sema = try #require(ctx.sema)
            let symbols = sema.symbols
            let types = sema.types

            let pathSymbol = try #require(
                symbols.lookup(fqName: ["kotlin", "io", "path", "Path"].map(interner.intern))
            )
            let exceptionSymbol = try #require(
                symbols.lookup(fqName: ["kotlin", "Exception"].map(interner.intern))
            )
            let onErrorResultSymbol = try #require(
                symbols.lookup(fqName: ["kotlin", "io", "path", "OnErrorResult"].map(interner.intern))
            )
            let pathType = types.make(
                .classType(ClassType(classSymbol: pathSymbol, args: [], nullability: .nonNull))
            )
            let exceptionType = types.make(
                .classType(ClassType(classSymbol: exceptionSymbol, args: [], nullability: .nonNull))
            )
            let onErrorResultType = types.make(
                .classType(ClassType(classSymbol: onErrorResultSymbol, args: [], nullability: .nonNull))
            )
            let onErrorType = types.make(.functionType(FunctionType(
                params: [pathType, pathType, exceptionType],
                returnType: onErrorResultType,
                isSuspend: false,
                nullability: .nonNull
            )))

            let candidates = symbols.lookupAll(
                fqName: ["kotlin", "io", "path", "copyToRecursively"].map(interner.intern)
            )
            let overwriteOverload = try #require(candidates.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID) else { return false }
                return signature.receiverType == pathType
                    && signature.parameterTypes == [pathType, onErrorType, types.booleanType, types.booleanType]
                    && signature.returnType == pathType
            }, "overwrite overload of copyToRecursively must be registered")

            #expect(
                symbols.externalLinkName(for: overwriteOverload) == "kk_path_copyToRecursively_overwrite",
                "overwrite overload must bind to kk_path_copyToRecursively_overwrite"
            )

            let signature = try #require(symbols.functionSignature(for: overwriteOverload))
            #expect(signature.receiverType == pathType)
            #expect(signature.returnType == pathType)
            #expect(signature.parameterTypes.count == 4)
        }
    }

    // MARK: - copyAction overload

    @Test func testPathCopyToRecursivelyCopyActionResolvesWithAllArguments() throws {
        let source = """
        import kotlin.Exception
        import kotlin.io.path.CopyActionContext
        import kotlin.io.path.CopyActionResult
        import kotlin.io.path.OnErrorResult
        import kotlin.io.path.Path
        import kotlin.io.path.copyToRecursively

        fun copyTree(
            source: Path,
            target: Path,
            onError: (Path, Path, Exception) -> OnErrorResult,
            copyAction: CopyActionContext.(Path, Path) -> CopyActionResult
        ): Path {
            return source.copyToRecursively(target, onError, true, copyAction)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(
                errors.isEmpty,
                "Path.copyToRecursively(target, onError, followLinks, copyAction) should resolve without errors, got: \(errors.map { "\($0.code): \($0.message)" })"
            )
        }
    }

    @Test func testPathCopyToRecursivelyCopyActionSignatureAndRuntimeLink() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let interner = ctx.interner
            let sema = try #require(ctx.sema)
            let symbols = sema.symbols
            let types = sema.types

            let pathSymbol = try #require(
                symbols.lookup(fqName: ["kotlin", "io", "path", "Path"].map(interner.intern))
            )
            let exceptionSymbol = try #require(
                symbols.lookup(fqName: ["kotlin", "Exception"].map(interner.intern))
            )
            let onErrorResultSymbol = try #require(
                symbols.lookup(fqName: ["kotlin", "io", "path", "OnErrorResult"].map(interner.intern))
            )
            let copyActionContextSymbol = try #require(
                symbols.lookup(fqName: ["kotlin", "io", "path", "CopyActionContext"].map(interner.intern))
            )
            let copyActionResultSymbol = try #require(
                symbols.lookup(fqName: ["kotlin", "io", "path", "CopyActionResult"].map(interner.intern))
            )
            let pathType = types.make(
                .classType(ClassType(classSymbol: pathSymbol, args: [], nullability: .nonNull))
            )
            let exceptionType = types.make(
                .classType(ClassType(classSymbol: exceptionSymbol, args: [], nullability: .nonNull))
            )
            let onErrorResultType = types.make(
                .classType(ClassType(classSymbol: onErrorResultSymbol, args: [], nullability: .nonNull))
            )
            let copyActionContextType = types.make(
                .classType(ClassType(classSymbol: copyActionContextSymbol, args: [], nullability: .nonNull))
            )
            let copyActionResultType = types.make(
                .classType(ClassType(classSymbol: copyActionResultSymbol, args: [], nullability: .nonNull))
            )
            let onErrorType = types.make(.functionType(FunctionType(
                params: [pathType, pathType, exceptionType],
                returnType: onErrorResultType,
                isSuspend: false,
                nullability: .nonNull
            )))
            let copyActionType = types.make(.functionType(FunctionType(
                receiver: copyActionContextType,
                params: [pathType, pathType],
                returnType: copyActionResultType,
                isSuspend: false,
                nullability: .nonNull
            )))

            let candidates = symbols.lookupAll(
                fqName: ["kotlin", "io", "path", "copyToRecursively"].map(interner.intern)
            )
            let copyActionOverload = try #require(candidates.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID) else { return false }
                return signature.receiverType == pathType
                    && signature.parameterTypes == [pathType, onErrorType, types.booleanType, copyActionType]
                    && signature.returnType == pathType
            }, "copyAction overload of copyToRecursively must be registered")

            #expect(
                symbols.externalLinkName(for: copyActionOverload) == "kk_path_copyToRecursively_copyAction",
                "copyAction overload must bind to kk_path_copyToRecursively_copyAction"
            )

            let signature = try #require(symbols.functionSignature(for: copyActionOverload))
            #expect(signature.receiverType == pathType)
            #expect(signature.returnType == pathType)
            #expect(signature.parameterTypes.count == 4)
        }
    }

    // MARK: - both overloads registered

    @Test func testBothCopyToRecursivelyOverloadsAreRegistered() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let interner = ctx.interner
            let sema = try #require(ctx.sema)
            let symbols = sema.symbols

            let candidates = symbols.lookupAll(
                fqName: ["kotlin", "io", "path", "copyToRecursively"].map(interner.intern)
            )
            #expect(
                candidates.count >= 2,
                "At least two copyToRecursively overloads (overwrite and copyAction) must be registered"
            )

            let linkNames = Set(candidates.compactMap { symbols.externalLinkName(for: $0) })
            #expect(
                linkNames.contains("kk_path_copyToRecursively_overwrite"),
                "overwrite overload must be present"
            )
            #expect(
                linkNames.contains("kk_path_copyToRecursively_copyAction"),
                "copyAction overload must be present"
            )
        }
    }
}
#endif
