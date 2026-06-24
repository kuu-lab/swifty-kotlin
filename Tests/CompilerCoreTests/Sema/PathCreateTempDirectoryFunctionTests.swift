#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// STDLIB-IO-PATH-FN-012: Validates that the top-level `kotlin.io.path.createTempDirectory`
/// functions resolve through Sema and yield a `kotlin.io.path.Path` return value.
///
/// Two overloads are covered:
/// - `createTempDirectory(directory: Path?, prefix: String?, vararg attributes: FileAttribute<*>): Path`
/// - `createTempDirectory(prefix: String?, vararg attributes: FileAttribute<*>): Path`
///
/// Both are registered in
/// `Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+SyntheticPathStubs.swift`
/// and bound to the runtime helpers declared in `Sources/RuntimeABI/RuntimeABISpec.swift`.
@Suite
struct PathCreateTempDirectoryFunctionTests {
    private func topLevelCallExprIDs(
        named name: String,
        in ast: ASTModule,
        interner: StringInterner
    ) -> [ExprID] {
        ast.arena.exprs.indices.compactMap { index in
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  case let .call(callee, _, _, _) = expr
            else {
                return nil
            }
            // Callee is a name expression whose text is the function name.
            if case let .nameRef(text, _) = ast.arena.expr(callee),
               interner.resolve(text) == name {
                return exprID
            }
            return nil
        }
    }

    // MARK: - createTempDirectory(prefix, attributes) overload

    @Test func testCreateTempDirectoryPrefixAttributesResolvesWithPrefixOnly() throws {
        let source = """
        import kotlin.io.path.Path
        import kotlin.io.path.createTempDirectory

        fun makeTempDir(): Path {
            return createTempDirectory("kswiftk-test-")
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(
                !ctx.diagnostics.hasError,
                Comment(rawValue: "createTempDirectory(prefix) should resolve without errors: "
                    + ctx.diagnostics.diagnostics.filter { $0.severity == .error }.map(\.message).joined(separator: ", "))
            )
        }
    }

    @Test func testCreateTempDirectoryPrefixAttributesResolvesWithDefaultPrefix() throws {
        let source = """
        import kotlin.io.path.Path
        import kotlin.io.path.createTempDirectory

        fun makeTempDir(): Path {
            return createTempDirectory()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(
                !ctx.diagnostics.hasError,
                Comment(rawValue: "createTempDirectory() with default prefix should resolve without errors: "
                    + ctx.diagnostics.diagnostics.filter { $0.severity == .error }.map(\.message).joined(separator: ", "))
            )
        }
    }

    @Test func testCreateTempDirectoryPrefixAttributesFunctionSignatureAndRuntimeLink() throws {
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
            let fileAttributeSymbol = try #require(
                symbols.lookup(fqName: ["java", "nio", "file", "attribute", "FileAttribute"].map(interner.intern))
            )
            let pathType = types.make(
                .classType(ClassType(classSymbol: pathSymbol, args: [], nullability: .nonNull))
            )
            let nullableStringType = types.makeNullable(types.stringType)
            let fileAttributeStarType = types.make(
                .classType(ClassType(classSymbol: fileAttributeSymbol, args: [.star], nullability: .nonNull))
            )

            let candidates = symbols.lookupAll(
                fqName: ["kotlin", "io", "path", "createTempDirectory"].map(interner.intern)
            )
            let createTempDir = try #require(candidates.first { symbolID in
                guard let sig = symbols.functionSignature(for: symbolID) else { return false }
                return sig.receiverType == nil
                    && sig.parameterTypes == [nullableStringType, fileAttributeStarType]
                    && sig.returnType == pathType
            }, "Expected to find createTempDirectory(prefix, attributes) overload")

            #expect(
                symbols.externalLinkName(for: createTempDir) == "kk_path_createTempDirectory_prefix_attributes",
                "createTempDirectory(prefix, attributes) must bind to kk_path_createTempDirectory_prefix_attributes"
            )
            let signature = try #require(symbols.functionSignature(for: createTempDir))
            #expect(signature.valueParameterHasDefaultValues == [true, false])
            #expect(signature.valueParameterIsVararg == [false, true])
            #expect(signature.returnType == pathType)
            #expect(signature.receiverType == nil)
        }
    }

    @Test func testCreateTempDirectoryPrefixCallExpressionTypedAsPath() throws {
        let source = """
        import kotlin.io.path.Path
        import kotlin.io.path.createTempDirectory

        fun makeTempDir(): Path {
            val a = createTempDirectory("kswiftk-")
            val b = createTempDirectory()
            return a
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(
                !ctx.diagnostics.hasError,
                Comment(rawValue: "createTempDirectory calls should resolve without errors: "
                    + ctx.diagnostics.diagnostics.map(\.message).joined(separator: ", "))
            )

            let interner = ctx.interner
            let sema = try #require(ctx.sema)
            let symbols = sema.symbols
            let types = sema.types
            let ast = try #require(ctx.ast)

            let pathSymbol = try #require(
                symbols.lookup(fqName: ["kotlin", "io", "path", "Path"].map(interner.intern))
            )
            let pathType = types.make(
                .classType(ClassType(classSymbol: pathSymbol, args: [], nullability: .nonNull))
            )
            let callExprs = topLevelCallExprIDs(named: "createTempDirectory", in: ast, interner: interner)
            #expect(callExprs.count == 2, "Expected 2 createTempDirectory call expressions")
            for callExpr in callExprs {
                #expect(
                    sema.bindings.exprTypes[callExpr] == pathType,
                    "Each createTempDirectory() call expression must be typed as kotlin.io.path.Path"
                )
            }
        }
    }

    // MARK: - createTempDirectory(directory, prefix, attributes) overload

    @Test func testCreateTempDirectoryDirectoryPrefixAttributesResolvesWithDirectory() throws {
        let source = """
        import java.nio.file.attribute.FileAttribute
        import kotlin.io.path.Path
        import kotlin.io.path.createTempDirectory

        fun makeTempDir(baseDir: Path, attr: FileAttribute<*>): Path {
            return createTempDirectory(baseDir, "kswiftk-test-", attr)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(
                !ctx.diagnostics.hasError,
                Comment(rawValue: "createTempDirectory(directory, prefix, attributes) should resolve without errors: "
                    + ctx.diagnostics.diagnostics.filter { $0.severity == .error }.map(\.message).joined(separator: ", "))
            )
        }
    }

    @Test func testCreateTempDirectoryDirectoryPrefixAttributesFunctionSignatureAndRuntimeLink() throws {
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
            let fileAttributeSymbol = try #require(
                symbols.lookup(fqName: ["java", "nio", "file", "attribute", "FileAttribute"].map(interner.intern))
            )
            let pathType = types.make(
                .classType(ClassType(classSymbol: pathSymbol, args: [], nullability: .nonNull))
            )
            let nullablePathType = types.makeNullable(pathType)
            let nullableStringType = types.makeNullable(types.stringType)
            let fileAttributeStarType = types.make(
                .classType(ClassType(classSymbol: fileAttributeSymbol, args: [.star], nullability: .nonNull))
            )

            let candidates = symbols.lookupAll(
                fqName: ["kotlin", "io", "path", "createTempDirectory"].map(interner.intern)
            )
            let createTempDir = try #require(candidates.first { symbolID in
                guard let sig = symbols.functionSignature(for: symbolID) else { return false }
                return sig.receiverType == nil
                    && sig.parameterTypes == [nullablePathType, nullableStringType, fileAttributeStarType]
                    && sig.returnType == pathType
            }, "Expected to find createTempDirectory(directory, prefix, attributes) overload")

            #expect(
                symbols.externalLinkName(for: createTempDir) == "kk_path_createTempDirectory_directory_prefix_attributes",
                "createTempDirectory(directory, prefix, attributes) must bind to kk_path_createTempDirectory_directory_prefix_attributes"
            )
            let signature = try #require(symbols.functionSignature(for: createTempDir))
            #expect(signature.valueParameterHasDefaultValues == [false, true, false])
            #expect(signature.valueParameterIsVararg == [false, false, true])
            #expect(signature.returnType == pathType)
            #expect(signature.receiverType == nil)
        }
    }
}
#endif
