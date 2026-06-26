@testable import CompilerCore
import XCTest

final class StringHOFMigrationText008Tests: XCTestCase {
    func testStringHOFsResolveToBundledKotlinSource() throws {
        let source = """
        fun text008(value: String): Any? {
            val filtered = value.filter { it != 'x' }
            val filterNot = value.filterNot { it == 'x' }
            val filterIndexed = value.filterIndexed { index, ch -> index == 0 || ch != 'x' }
            val mapped = value.map { it }
            val mappedIndexed = value.mapIndexed { index, ch -> ch }
            val mappedNotNull = value.mapNotNull { ch -> if (ch == 'x') null else ch }
            val flatMapped = value.flatMap { listOf(it, it) }
            val counted = value.count { it == 'x' }
            val anyX = value.any { it == 'x' }
            val allLetters = value.all { it.isLetter() }
            val noneDigits = value.none { it.isDigit() }
            val folded = value.fold(0) { acc, ch -> acc }
            val foldedIndexed = value.foldIndexed(0) { index, acc, ch -> acc }
            val reduced = value.reduce { acc, ch -> if (ch > acc) ch else acc }
            val reducedIndexed = value.reduceIndexed { index, acc, ch -> if (index > 0) ch else acc }
            val scanned = value.scan(0) { acc, ch -> acc }
            val scannedIndexed = value.scanIndexed(0) { index, acc, ch -> acc }
            val runningFold = value.runningFold("") { acc, ch -> acc }
            val runningFoldIndexed = value.runningFoldIndexed("") { index, acc, ch -> acc }
            val runningReduce = value.runningReduce { acc, ch -> if (ch > acc) ch else acc }
            val runningReduceIndexed = value.runningReduceIndexed { index, acc, ch -> if (index > 0) ch else acc }
            value.forEach { ch -> ch.toString() }
            value.forEachIndexed { index, ch -> index.toString() + ch.toString() }
            value.onEach { ch -> ch.toString() }
            value.onEachIndexed { index, ch -> index.toString() + ch.toString() }
            return runningReduceIndexed
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnosticSummary = ctx.diagnostics.diagnostics
                .map { "\($0.code): \($0.message)" }
                .joined(separator: " | ")
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Expected String HOF source migration calls to type-check, got: \(diagnosticSummary)"
            )

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let userFileID = try XCTUnwrap(ctx.sourceManager.fileID(forPath: path))
            let migratedNames: Set<String> = [
                "filter", "filterNot", "filterIndexed",
                "map", "mapIndexed", "mapNotNull", "flatMap",
                "count", "any", "all", "none",
                "fold", "foldIndexed", "reduce", "reduceIndexed",
                "scan", "scanIndexed", "runningFold", "runningFoldIndexed",
                "runningReduce", "runningReduceIndexed",
                "forEach", "forEachIndexed", "onEach", "onEachIndexed",
            ]
            var seenNames = Set<String>()

            for index in ast.arena.exprs.indices {
                let exprID = ExprID(rawValue: Int32(index))
                guard let expr = ast.arena.expr(exprID),
                      case let .memberCall(_, callee, _, _, range) = expr,
                      range.start.file == userFileID
                else {
                    continue
                }
                let name = ctx.interner.resolve(callee)
                guard migratedNames.contains(name) else {
                    continue
                }
                seenNames.insert(name)
                let chosen = try XCTUnwrap(
                    sema.bindings.callBinding(for: exprID)?.chosenCallee,
                    "Expected call binding for \(name)"
                )
                XCTAssertNil(
                    sema.symbols.externalLinkName(for: chosen),
                    "\(name) should resolve to bundled Kotlin source, not a kk_string_* synthetic ABI stub"
                )
            }

            XCTAssertEqual(seenNames, migratedNames)
        }
    }
}
