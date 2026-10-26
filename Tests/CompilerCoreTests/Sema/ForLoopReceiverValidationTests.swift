@testable import CompilerCore
import Testing
import TestStdlibCache

@Suite
struct ForLoopReceiverValidationTests {
    private func makeNameDestructuringContext(
        _ source: String,
        complete: Bool = true
    ) -> CompilationContext {
        TestStdlibCache.shared.prepare()
        return makeContextFromSource(
            source,
            frontendFlags: complete ? ["name-based-destructuring=complete"] : [],
            allowDefaultStdlibLibrary: true
        )
    }

    @Test(arguments: ["X()", "5", "true", "object {}", "null"])
    func rejectsNonIterableReceivers(receiver: String) throws {
        let ctx = makeContextFromSource("""
        class X { val v = 1 }
        fun main() {
            var n = 0
            for (e in \(receiver)) n++
            println(n)
        }
        """)
        do { try runSema(ctx) } catch {}
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.contains { $0.code == "KSWIFTK-SEMA-0172" }, "\(errors)")
    }

    @Test
    func rejectsFloatingPointRangesWithoutIterator() throws {
        TestStdlibCache.shared.prepare()
        let ctx = makeContextFromSource("""
        fun test() {
            for (doubleValue in 1.0..5.0) {}
            for (floatValue in 1f..5f) {}
        }
        """, allowDefaultStdlibLibrary: true)
        do { try runSema(ctx) } catch {}
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        let missingIteratorErrors = errors.filter { $0.code == "KSWIFTK-SEMA-0172" }
        #expect(missingIteratorErrors.count == 2, "\(errors)")
    }

    @Test
    func acceptsFloatingPointRangeWithIteratorOperator() throws {
        TestStdlibCache.shared.prepare()
        let ctx = makeContextFromSource("""
        import kotlin.ranges.ClosedFloatingPointRange
        operator fun ClosedFloatingPointRange<Double>.iterator(): Iterator<Double> =
            listOf(start, endInclusive).iterator()
        fun test() {
            for (value in 1.0..5.0) {}
        }
        """, allowDefaultStdlibLibrary: true)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test(arguments: ["List<Int>", "String", "IntArray", "Iterator<Int>"])
    func rejectsNullableReceivers(type: String) throws {
        let ctx = makeContextFromSource("""
        fun test(value: \(type)?) {
            for (e in value) {}
        }
        """)
        do { try runSema(ctx) } catch {}
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.contains { $0.code == "KSWIFTK-SEMA-0172" }, "\(errors)")
    }

    @Test
    func rejectsNonOperatorIteratorAndInvalidDestructuringReceiver() throws {
        let ctx = makeContextFromSource("""
        class X {
            fun iterator(): Iterator<Int> = listOf(1).iterator()
        }
        fun test() {
            for (e in X()) {}
            for ((a, b) in 5) {}
        }
        """)
        do { try runSema(ctx) } catch {}
        let errors = ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-0172" }
        #expect(errors.count == 2, "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func rejectsIteratorReturningNonIteratorType() throws {
        let ctx = makeContextFromSource("""
        class C { operator fun iterator() = 1 }
        fun test() {
            for (e in C()) {}
        }
        """)
        do { try runSema(ctx) } catch {}
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.filter { $0.code == "KSWIFTK-SEMA-0172" }.count == 2, "\(errors)")
    }

    @Test(arguments: [true, false])
    func rejectsNonOperatorHasNextOrNextOnIteratorReturnType(hasNextIsOperator: Bool) throws {
        let hasNextModifier = hasNextIsOperator ? "operator " : ""
        let nextModifier = hasNextIsOperator ? "" : "operator "
        let ctx = makeContextFromSource("""
        class It {
            \(hasNextModifier)fun hasNext(): Boolean = false
            \(nextModifier)fun next(): Int = 1
        }
        class C { operator fun iterator(): It = It() }
        fun test() {
            for (e in C()) {}
        }
        """)
        do { try runSema(ctx) } catch {}
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.filter { $0.code == "KSWIFTK-SEMA-0432" }.count == 1, "\(errors)")
    }

    @Test
    func acceptsSupportedIterationAndSmartCasts() throws {
        let ctx = makeContextFromSource("""
        class Counter {
            operator fun hasNext(): Boolean = false
            operator fun next(): Int = 1
        }
        class Bag { operator fun iterator(): Counter = Counter() }
        fun test(xs: List<Int>?, sequence: Sequence<Int>, text: CharSequence) {
            for (e in listOf(1, 2)) {}
            for (e in arrayOf(1, 2)) {}
            for (e in intArrayOf(1, 2)) {}
            for (e in "str") {}
            for (e in text) {}
            for (e in 1..3) {}
            for (e in 1 until 3) {}
            for (e in sequence) {}
            for (e in listOf(1).iterator()) {}
            for (e in Bag()) {}
            for ((a, b) in listOf(Pair(1, 2))) {}
            if (xs != null) { for (e in xs) {} }
        }
        fun <T : Iterable<Int>> generic(xs: T) { for (e in xs) {} }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func acceptsTreeMapDirectIterationAndEntryDestructuring() throws {
        let ctx = makeContextFromSource("""
        import java.util.TreeMap

        fun test() {
            val values = TreeMap<Char, String>()
            values['A'] = "1"
            for (entry in values) {
                println("${entry.key}=${entry.value}")
            }
            for ((key, value) in values) {
                println("$key=$value")
            }
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func acceptsSquareBracketDestructuringInForLoop() throws {
        let ctx = makeContextFromSource("""
        data class C(val first: Int, val second: Int)
        fun main() {
            for ([a, b] in arrayOf(C(1, 2))) {
                println(a)
                println(b)
            }
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")

        let ast = try #require(ctx.ast)
        let names = ast.arena.exprs.compactMap { expression -> [InternedString?]? in
            guard case let .forDestructuringExpr(names, _, _, _, _) = expression,
                  names.map({ $0.map(ctx.interner.resolve) }) == ["a", "b"]
            else {
                return nil
            }
            return names
        }.first
        #expect(names?.map { $0.map(ctx.interner.resolve) } == ["a", "b"])
    }

    @Test
    func completeNameBasedDestructuringResolvesParenthesizedNames() throws {
        let ctx = makeNameDestructuringContext("""
        class C(val a: Int, val b: Int)
        fun main() {
            for ((a, b) in arrayOf(C(1, 2))) println("$a,$b")
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")

        let ast = try #require(ctx.ast)
        let loopIndex = try #require(ast.arena.exprs.indices.first { index in
            if case .forDestructuringExpr = ast.arena.exprs[index] { return true }
            return false
        })
        let loopID = ExprID(rawValue: Int32(loopIndex))
        #expect(ctx.sema?.bindings.destructuringProperty(for: loopID, index: 0) != nil)
        #expect(ctx.sema?.bindings.destructuringProperty(for: loopID, index: 1) != nil)
    }

    @Test
    func completeNameBasedDestructuringAllowsStatementBodies() throws {
        let ctx = makeNameDestructuringContext("""
        class P(val first: String, val second: Int)

        fun singleExpressionBody(x: P): Boolean {
            for ((first, second) in arrayOf(x))
                if (first != "OK" || second != 1) return false
            return true
        }

        fun blockBody(x: P): Boolean {
            for ((first, second) in arrayOf(x)) {
                if (first != "OK" || second != 1) return false
            }
            return true
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func nameBasedDestructuringDeclarationResolvesExplicitPropertyAliases() throws {
        let source = """
        class Tuple(val first: Int, val second: Int)
        fun test(x: Tuple): Int {
            val (a = first, b = second) = x
            return a + b
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                frontendFlags: ["name-based-destructuring=complete"],
                includeStdlib: false,
                allowDefaultStdlibLibrary: false
            )
            try runSema(ctx)
            let sourceDiagnostics = diagnosticsForPath(path, in: ctx)
            #expect(!sourceDiagnostics.hasError, "\(sourceDiagnostics)")

            let ast = try #require(ctx.ast)
            let sourceFile = try #require(ctx.sourceManager.fileID(forPath: path))
            let declarationIndex = try #require(ast.arena.exprs.indices.first { index in
                let id = ExprID(rawValue: Int32(index))
                guard case .destructuringDecl = ast.arena.exprs[index] else { return false }
                return ast.arena.exprRange(id)?.start.file == sourceFile
            })
            let declarationID = ExprID(rawValue: Int32(declarationIndex))
            let firstBinding = try #require(ctx.sema?.bindings.destructuringProperty(for: declarationID, index: 0))
            let secondBinding = try #require(ctx.sema?.bindings.destructuringProperty(for: declarationID, index: 1))
            #expect(ctx.sema?.symbols.symbol(firstBinding.propertySymbol)?.name == ctx.interner.intern("first"))
            #expect(ctx.sema?.symbols.symbol(secondBinding.propertySymbol)?.name == ctx.interner.intern("second"))
        }
    }

    @Test
    func nameBasedFullFormDestructuringBindsLocalForAndLambdaEntries() throws {
        let source = """
        class Tuple(val first: String, val second: Int)
        class Cursor(val value: Tuple) {
            operator fun hasNext(): Boolean = false
            operator fun next(): Tuple = value
        }
        class Values(val value: Tuple) {
            operator fun iterator(): Cursor = Cursor(value)
        }

        fun localDeclarations(x: Tuple): Boolean {
            (val a = first, val b = second) = x
            if (a != "OK" || b != 1) return false

            (val second) = x
            if (second != 1) return false

            (val second: Int, val first: String) = x
            if (first != "OK" || second != 1) return false

            (var first, var second) = x
            first = "KO"
            second = 2
            return first == "KO" && second == 2
        }

        fun forLoop(x: Tuple): Boolean {
            for ((val first, val second) in Values(x)) {
                if (first != "OK" || second != 1) return false
            }
            return true
        }

        fun lambdaParameter(x: Tuple): Boolean {
            val check: (Tuple) -> Boolean = { (val first, val second) ->
                first == "OK" && second == 1
            }
            return check(x)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                frontendFlags: ["name-based-destructuring=complete"],
                includeStdlib: false
            )
            try runSema(ctx)
            let sourceDiagnostics = diagnosticsForPath(path, in: ctx)
            #expect(!sourceDiagnostics.hasError, "\(sourceDiagnostics)")
        }
    }

    @Test
    func nameBasedForLoopDestructuringResolvesExplicitPropertyAliases() throws {
        let source = """
        class Tuple(val first: Int, val second: Int)
        class Cursor {
            operator fun hasNext(): Boolean = false
            operator fun next(): Tuple = Tuple(1, 2)
        }
        class Values {
            operator fun iterator(): Cursor = Cursor()
        }
        fun test(values: Values): Int {
            var total = 0
            for ((a = first, b = second) in values) total = a + b
            return total
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                frontendFlags: ["name-based-destructuring=complete"],
                includeStdlib: false,
                allowDefaultStdlibLibrary: false
            )
            try runSema(ctx)
            let sourceDiagnostics = diagnosticsForPath(path, in: ctx)
            #expect(!sourceDiagnostics.hasError, "\(sourceDiagnostics)")

            let ast = try #require(ctx.ast)
            let sourceFile = try #require(ctx.sourceManager.fileID(forPath: path))
            let loopIndex = try #require(ast.arena.exprs.indices.first { index in
                let id = ExprID(rawValue: Int32(index))
                guard case .forDestructuringExpr = ast.arena.exprs[index] else { return false }
                return ast.arena.exprRange(id)?.start.file == sourceFile
                    && ctx.sema?.bindings.destructuringProperty(for: id, index: 0) != nil
            })
            let loopID = ExprID(rawValue: Int32(loopIndex))
            if case let .forDestructuringExpr(names, _, _, _, _) = ast.arena.exprs[loopIndex] {
                #expect(names.map { $0.map(ctx.interner.resolve) } == ["a", "b"])
            } else {
                Issue.record("Expected a destructuring for-loop expression")
            }
            let firstBinding = try #require(ctx.sema?.bindings.destructuringProperty(for: loopID, index: 0))
            let secondBinding = try #require(ctx.sema?.bindings.destructuringProperty(for: loopID, index: 1))
            #expect(ctx.sema?.symbols.symbol(firstBinding.propertySymbol)?.name == ctx.interner.intern("first"))
            #expect(ctx.sema?.symbols.symbol(secondBinding.propertySymbol)?.name == ctx.interner.intern("second"))
        }
    }

    @Test
    func completeNameBasedDestructuringDoesNotFallbackToComponentFunctions() throws {
        let ctx = makeNameDestructuringContext("""
        data class C(val first: Int, val second: Int)
        fun test() {
            for ((a, b) in arrayOf(C(1, 2))) {}
        }
        """)
        do { try runSema(ctx) } catch {}
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.contains { $0.code == "KSWIFTK-SEMA-0022" }, "\(errors)")
        #expect(!errors.contains { $0.code == "KSWIFTK-SEMA-0087" }, "\(errors)")
    }

    @Test
    func completeNameBasedDestructuringDoesNotApplyToSquareBrackets() throws {
        let ctx = makeNameDestructuringContext("""
        class C(val a: Int, val b: Int)
        fun test() {
            for ([a, b] in arrayOf(C(1, 2))) {}
        }
        """)
        do { try runSema(ctx) } catch {}
        #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0087" })
    }

    @Test
    func completeNameBasedDestructuringRejectsNullableElements() throws {
        let ctx = makeNameDestructuringContext("""
        class C(val a: Int, val b: Int)
        fun test(values: Array<C?>) {
            for ((a, b) in values) {}
        }
        """)
        do { try runSema(ctx) } catch {}
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.contains { $0.code == "KSWIFTK-SEMA-0026" }, "\(errors)")
        #expect(!errors.contains { $0.code == "KSWIFTK-SEMA-0022" }, "\(errors)")
    }

    @Test
    func defaultDestructuringStillRequiresComponentFunctions() throws {
        let ctx = makeNameDestructuringContext("""
        class C(val a: Int, val b: Int)
        fun test() {
            for ((a, b) in arrayOf(C(1, 2))) {}
        }
        """, complete: false)
        do { try runSema(ctx) } catch {}
        #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0087" })
    }

    @Test
    func acceptsBreakToLabeledDestructuringForLoop() throws {
        let ctx = makeContextFromSource("""
        fun main() {
            val rows = listOf("a", "b")
            find@ for ((r, row) in rows.withIndex()) {
                for ((i, c) in row.withIndex()) {
                    if (c == 'a') break@find
                }
            }
            println("done")
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

}
