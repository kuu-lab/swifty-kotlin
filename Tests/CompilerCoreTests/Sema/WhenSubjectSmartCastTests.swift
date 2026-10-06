#if canImport(Testing)
@testable import CompilerCore
import Testing

/// A lambda parameter (`it` or a named parameter) used as a `when` subject
/// must be smart-cast in `is` branches just like a regular function
/// parameter. The lambda parameter's symbol is a synthetic ID that is never
/// registered in the symbol table, which used to make
/// `TypeCheckHelpers.isStableLocalSymbol` treat it as unstable and skip the
/// narrowing entirely (while the same synthetic ID was already treated as
/// stable by the `if (it is T)` narrowing path in DataFlow/Analysis.swift's
/// `resolveLocalVariable`).
@Suite
struct WhenSubjectSmartCastTests {
    @Test func testSealedWhenInterfaceBranchCoversImplementingSubclasses() throws {
        let source = """
        sealed class Grammar
        interface SimpleGrammar { val g: Grammar }
        class MaybeG(override val g: Grammar) : Grammar(), SimpleGrammar
        class ManyG(override val g: Grammar) : Grammar(), SimpleGrammar
        class SeqG(val gs: List<Grammar>) : Grammar()
        class OrG(val gs: List<Grammar>) : Grammar()
        fun f(g: Grammar) = when (g) {
            is SeqG -> 1
            is OrG -> 2
            is SimpleGrammar -> 3
        }
        fun Grammar.classify() = when (this) {
            is SeqG, is OrG -> 1
            is SimpleGrammar -> 2
        }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
    }

    @Test func testSealedWhenInterfaceBranchCoversInheritedImplementations() throws {
        let source = """
        interface Tag
        interface ChildTag : Tag
        open class Tagged : ChildTag
        sealed interface Node
        class Leaf : Tagged(), Node
        object End : Node
        class Holder(val node: Node)
        fun classify(holder: Holder) = when (holder.node) {
            is Tag -> 1
            End -> 2
        }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
    }

    @Test func testSealedWhenInterfaceBranchReportsOnlyUncoveredSubclass() throws {
        let source = """
        sealed class Grammar
        interface SimpleGrammar
        class MaybeG : Grammar(), SimpleGrammar
        class ManyG : Grammar(), SimpleGrammar
        class SeqG : Grammar()
        class OrG : Grammar()
        fun classify(g: Grammar) = when (g) {
            is SimpleGrammar -> 1
            is SeqG -> 2
        }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        let diagnostics = ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-0071" }
        #expect(diagnostics.count == 1)
        #expect(diagnostics.first?.message == "Non-exhaustive when expression on sealed type. Missing branches: OrG.")
    }

    @Test func testNullableSealedWhenInterfaceBranchStillRequiresNull() throws {
        let source = """
        sealed interface Node
        interface Tag
        class Leaf : Node, Tag
        fun complete(node: Node?) = when (node) {
            is Tag -> 1
            null -> 2
        }
        fun incomplete(node: Node?) = when (node) {
            is Tag -> 1
        }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.count == 1)
        #expect(errors.first?.code == "KSWIFTK-SEMA-0004")
        assertNoDiagnostic("KSWIFTK-SEMA-0071", in: ctx)
    }

    @Test func testGuardedAndNegatedInterfaceBranchesDoNotCoverImplementers() throws {
        let source = """
        sealed interface Node
        interface Tag
        class Leaf : Node, Tag
        object End : Node
        fun guarded(node: Node, flag: Boolean) = when (node) {
            is Tag if flag -> 1
            End -> 2
        }
        fun negated(node: Node) = when (node) {
            !is Tag -> 1
            End -> 2
        }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        let diagnostics = ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-0071" }
        #expect(diagnostics.count == 2)
        #expect(diagnostics.allSatisfy { $0.message.contains("Missing branches: Leaf.") })
    }

    @Test func testUnrelatedInterfaceWithSameShortNameDoesNotCoverSubclass() throws {
        let source = """
        sealed interface Node {
            class Leaf : Node
            object End : Node
        }
        interface Other {
            interface Leaf
        }
        fun classify(node: Node) = when (node) {
            is Other.Leaf -> 1
            is Node.End -> 2
        }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        assertHasDiagnostic("KSWIFTK-SEMA-0071", in: ctx)
    }

    @Test func testLambdaParameterWhenSubjectSmartCast() throws {
        let source = """
        sealed interface Shape
        class Circle(val r: Double) : Shape
        class Rect(val w: Double, val h: Double) : Shape

        fun describeAll(shapes: List<Shape>): List<String> {
            val byIt = shapes.map { when (it) { is Circle -> "c${it.r}"; is Rect -> "r${it.w}x${it.h}" } }
            val byNamed = shapes.map { s -> when (s) { is Circle -> "c${s.r}"; is Rect -> "r${s.w}x${s.h}" } }
            return byIt + byNamed
        }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
    }

    @Test func testExtensionReceiverThisWhenSubjectSmartCastAndExhaustiveness() throws {
        let source = """
        sealed class Result {
            data class Ok(val v: Int) : Result()
            data class Err(val msg: String) : Result()
        }
        fun Result.text() = when (this) { is Result.Ok -> "ok$v"; is Result.Err -> "err:$msg" }

        sealed class Top
        class A1(val a: Int) : Top()
        class B1(val b: String) : Top()
        fun Top.t() = when (this) { is A1 -> "a$a"; is B1 -> "b$b" }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-0071", in: ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-0004", in: ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
    }

    @Test func testQualifiedSealedSubjectWithReifiedAndIsBranchesIsExhaustive() throws {
        let source = """
        sealed interface Slot {
            class Task : Slot
            object Closed : Slot
            object Empty : Slot
        }
        class Holder(val previous: Slot)

        inline fun <reified TaskType> classify(holder: Holder): Int = when (holder.previous) {
            is TaskType -> 0
            is Slot.Task -> 1
            Slot.Closed -> 2
            Slot.Empty -> 3
        }
        inline fun <reified TaskType> classifyLocal(previous: Slot): Int = when (previous) {
            is TaskType -> 0
            is Slot.Task -> 1
            Slot.Closed -> 2
            Slot.Empty -> 3
        }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-0004", in: ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-0071", in: ctx)
    }

    @Test func testQualifiedSealedSubjectStillReportsMissingSubtype() throws {
        let source = """
        sealed interface Slot {
            class Task : Slot
            object Empty : Slot
        }
        class Holder(val previous: Slot)
        fun classify(holder: Holder): Int = when (holder.previous) {
            is Slot.Task -> 1
        }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        assertHasDiagnostic("KSWIFTK-SEMA-0071", in: ctx)
    }
}
#endif
