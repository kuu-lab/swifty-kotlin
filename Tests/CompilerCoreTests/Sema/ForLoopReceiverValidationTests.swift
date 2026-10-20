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
