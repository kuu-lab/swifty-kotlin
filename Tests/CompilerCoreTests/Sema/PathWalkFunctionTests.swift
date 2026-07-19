#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// STDLIB-IO-PATH-FN-039: Validates that the `walk` extension function on
/// `kotlin.io.path.Path` is wired through Sema with the expected
/// `vararg options: PathWalkOption` signature and resolves to `kk_path_walk`.
///
/// Kotlin signature:
///
///     public actual fun Path.walk(
///         vararg options: PathWalkOption
///     ): Sequence<Path>
@Suite
struct PathWalkFunctionTests {

    // MARK: - Basic resolution

    @Test func testPathWalkNoOptionsResolves() throws {
        let source = """
        import kotlin.io.path.Path
        import kotlin.io.path.walk

        fun walkAll(path: Path) {
            path.walk()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(
                errors.isEmpty,
                "Path.walk() with no options should resolve: \(errors.map { "\($0.code): \($0.message)" })"
            )
        }
    }

    @Test func testPathWalkBreadthFirstOptionResolves() throws {
        let source = """
        import kotlin.io.path.Path
        import kotlin.io.path.PathWalkOption
        import kotlin.io.path.walk

        fun walkBreadthFirst(path: Path) {
            path.walk(PathWalkOption.BREADTH_FIRST)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(
                errors.isEmpty,
                "Path.walk(BREADTH_FIRST) should resolve: \(errors.map { "\($0.code): \($0.message)" })"
            )
        }
    }

    @Test func testPathWalkFollowLinksOptionResolves() throws {
        let source = """
        import kotlin.io.path.Path
        import kotlin.io.path.PathWalkOption
        import kotlin.io.path.walk

        fun walkFollowLinks(path: Path) {
            path.walk(PathWalkOption.FOLLOW_LINKS)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(
                errors.isEmpty,
                "Path.walk(FOLLOW_LINKS) should resolve: \(errors.map { "\($0.code): \($0.message)" })"
            )
        }
    }

    @Test func testPathWalkMultipleOptionsResolve() throws {
        let source = """
        import kotlin.io.path.Path
        import kotlin.io.path.PathWalkOption
        import kotlin.io.path.walk

        fun walkWithAll(path: Path) {
            path.walk(PathWalkOption.BREADTH_FIRST, PathWalkOption.FOLLOW_LINKS)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(
                errors.isEmpty,
                "Path.walk(BREADTH_FIRST, FOLLOW_LINKS) should resolve: \(errors.map { "\($0.code): \($0.message)" })"
            )
        }
    }

    // MARK: - Return type

    @Test func testPathWalkReturnTypeIsSequenceOfPath() throws {
        let source = """
        import kotlin.io.path.Path
        import kotlin.io.path.walk
        import kotlin.sequences.Sequence

        fun allPaths(path: Path): Sequence<Path> {
            return path.walk()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(
                errors.isEmpty,
                "Path.walk() return type should be Sequence<Path>: \(errors.map { "\($0.code): \($0.message)" })"
            )
        }
    }

    // MARK: - Chained operations

    @Test func testPathWalkChainedToListResolves() throws {
        let source = """
        import kotlin.io.path.Path
        import kotlin.io.path.walk

        fun collectPaths(path: Path): List<Path> {
            return path.walk().toList()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(
                errors.isEmpty,
                "Path.walk().toList() should resolve: \(errors.map { "\($0.code): \($0.message)" })"
            )
        }
    }

    @Test func testPathWalkChainedFilterResolves() throws {
        let source = """
        import kotlin.io.path.Path
        import kotlin.io.path.walk

        fun onlyFiles(path: Path): List<Path> {
            return path.walk().filter { it.toString().endsWith(".kt") }.toList()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(
                errors.isEmpty,
                "Path.walk().filter { }.toList() should resolve: \(errors.map { "\($0.code): \($0.message)" })"
            )
        }
    }

    @Test func testPathWalkChainedForEachResolves() throws {
        let source = """
        import kotlin.io.path.Path
        import kotlin.io.path.walk

        fun printPaths(path: Path) {
            path.walk().forEach { println(it) }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(
                errors.isEmpty,
                "Path.walk().forEach { } should resolve: \(errors.map { "\($0.code): \($0.message)" })"
            )
        }
    }

    // MARK: - ABI surface inspection

    @Test func testPathWalkExtensionFunctionSurfaceIsRegistered() throws {
        let source = """
        import kotlin.io.path.Path
        import kotlin.io.path.PathWalkOption
        import kotlin.io.path.walk
        import kotlin.sequences.Sequence

        fun stub(path: Path): Sequence<Path> = path.walk()
        """

        try withTemporaryFile(contents: source) { filePath in
            let ctx = makeCompilationContext(inputs: [filePath])
            try runSema(ctx)
            #expect(
                !(ctx.diagnostics.hasError),
                "Path.walk() should resolve without errors: \(ctx.diagnostics.diagnostics.map(\.message))"
            )

            let interner = ctx.interner
            let sema = try #require(ctx.sema)
            let symbols = sema.symbols
            let types = sema.types

            let pathSymbol = try #require(
                symbols.lookup(fqName: ["kotlin", "io", "path", "Path"].map(interner.intern))
            )
            let walkOptionSymbol = try #require(
                symbols.lookup(fqName: ["kotlin", "io", "path", "PathWalkOption"].map(interner.intern))
            )
            let sequenceSymbol = try #require(
                symbols.lookup(fqName: ["kotlin", "sequences", "Sequence"].map(interner.intern))
            )

            let pathType = types.make(.classType(ClassType(classSymbol: pathSymbol, args: [], nullability: .nonNull)))
            let walkOptionType = types.make(.classType(ClassType(classSymbol: walkOptionSymbol, args: [], nullability: .nonNull)))
            let sequenceOfPathType = types.make(.classType(ClassType(
                classSymbol: sequenceSymbol,
                args: [.out(pathType)],
                nullability: .nonNull
            )))

            let walkSymbols = symbols.lookupAll(
                fqName: ["kotlin", "io", "path", "walk"].map(interner.intern)
            )
            let walk = try #require(
                walkSymbols.first { symbolID in
                    guard let signature = symbols.functionSignature(for: symbolID) else { return false }
                    return signature.receiverType == pathType
                        && signature.parameterTypes == [walkOptionType]
                        && signature.returnType == sequenceOfPathType
                },
                "Expected kotlin.io.path.walk with receiver=Path, params=[PathWalkOption], ret=Sequence<Path>"
            )

            #expect(symbols.externalLinkName(for: walk) == "kk_path_walk")

            let signature = try #require(symbols.functionSignature(for: walk))
            #expect(signature.valueParameterHasDefaultValues == [false])
            #expect(signature.valueParameterIsVararg == [true])
        }
    }
}
#endif
