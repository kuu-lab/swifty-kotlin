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


    // MARK: - Consolidated PathWalk Sema tests

    @Test

    func testPathWalkFunctions() throws {

        let cases: [(label: String, source: String)] = [

            ("testPathWalkNoOptionsResolves", """
            package sample0

                    import kotlin.io.path.Path
                    import kotlin.io.path.walk

                    fun walkAll(path: Path) {
                        path.walk()
                    }

            """),

            ("testPathWalkBreadthFirstOptionResolves", """
            package sample1

                    import kotlin.io.path.Path
                    import kotlin.io.path.PathWalkOption
                    import kotlin.io.path.walk

                    fun walkBreadthFirst(path: Path) {
                        path.walk(PathWalkOption.BREADTH_FIRST)
                    }

            """),

            ("testPathWalkFollowLinksOptionResolves", """
            package sample2

                    import kotlin.io.path.Path
                    import kotlin.io.path.PathWalkOption
                    import kotlin.io.path.walk

                    fun walkFollowLinks(path: Path) {
                        path.walk(PathWalkOption.FOLLOW_LINKS)
                    }

            """),

            ("testPathWalkMultipleOptionsResolve", """
            package sample3

                    import kotlin.io.path.Path
                    import kotlin.io.path.PathWalkOption
                    import kotlin.io.path.walk

                    fun walkWithAll(path: Path) {
                        path.walk(PathWalkOption.BREADTH_FIRST, PathWalkOption.FOLLOW_LINKS)
                    }

            """),

            ("testPathWalkReturnTypeIsSequenceOfPath", """
            package sample4

                    import kotlin.io.path.Path
                    import kotlin.io.path.walk
                    import kotlin.sequences.Sequence

                    fun allPaths(path: Path): Sequence<Path> {
                        return path.walk()
                    }

            """),

            ("testPathWalkChainedToListResolves", """
            package sample5

                    import kotlin.io.path.Path
                    import kotlin.io.path.walk

                    fun collectPaths(path: Path): List<Path> {
                        return path.walk().toList()
                    }

            """),

            ("testPathWalkChainedFilterResolves", """
            package sample6

                    import kotlin.io.path.Path
                    import kotlin.io.path.walk

                    fun onlyFiles(path: Path): List<Path> {
                        return path.walk().filter { it.toString().endsWith(".kt") }.toList()
                    }

            """),

            ("testPathWalkChainedForEachResolves", """
            package sample7

                    import kotlin.io.path.Path
                    import kotlin.io.path.walk

                    fun printPaths(path: Path) {
                        path.walk().forEach { println(it) }
                    }

            """),

            ("testPathWalkExtensionFunctionSurfaceIsRegistered", """
            package sample8

                    import kotlin.io.path.Path
                    import kotlin.io.path.PathWalkOption
                    import kotlin.io.path.walk
                    import kotlin.sequences.Sequence

                    fun stub(path: Path): Sequence<Path> = path.walk()

            """),

        ]

        let sources = cases.map { $0.source }

        try withTemporaryFiles(contents: sources) { paths in

            let ctx = makeCompilationContext(inputs: paths)

            try runSema(ctx)



            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }

            let diagnosticSummary = errors.map { "\($0.code): \($0.message)" }.joined(separator: " | ")

            #expect(

                errors.isEmpty,

                "Path.walk variants should resolve cleanly, got: \(diagnosticSummary)"

            )

        }

    }

}

#endif
