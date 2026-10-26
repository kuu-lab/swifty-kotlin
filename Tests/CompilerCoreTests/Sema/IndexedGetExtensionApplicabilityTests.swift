@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct IndexedGetExtensionApplicabilityTests {
    @Test
    func genericNullableOperatorGetUsesExpectedReturnType() throws {
        let ctx = makeContextFromSource("""
        interface Settings
        inline operator fun <reified T : Any> Settings.get(key: String): T? = null
        inline fun <reified T : Any> Settings.read(key: String): T? = null
        fun indexed(settings: Settings): Int? = settings["x"]
        fun directOperatorCall(settings: Settings): Int? = settings.get("x")
        fun ordinaryCall(settings: Settings): Int? = settings.read("x")
        fun explicitTypeArgument(settings: Settings): Int? = settings.get<Int>("x")
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let indexed = try #require(firstExprID(in: ast) { _, expr in
            guard case let .indexedAccess(_, _, range) = expr else { return false }
            return ctx.sourceManager.origin(of: range.start.file) == .user
        })
        #expect(sema.bindings.exprType(for: indexed) == sema.types.makeNullable(sema.types.intType))
    }

    @Test
    func integerLiteralIsContextualizedForFallbackExtension() throws {
        let ctx = makeContextFromSource("""
        class LongSlots { operator fun get(index: String): Int = 0 }
        class ByteSlots { operator fun get(index: String): Int = 0 }
        class UIntSlots { operator fun get(index: String): Int = 0 }
        operator fun LongSlots.get(index: Long): Int = 1
        operator fun ByteSlots.get(index: Byte): Int = 1
        operator fun UIntSlots.get(index: UInt): Int = 1
        fun probe(a: LongSlots, b: ByteSlots, c: UIntSlots) {
            a[0]
            b[0]
            c[0u]
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let indices = ast.arena.exprs.compactMap { expr -> ExprID? in
            guard case let .indexedAccess(_, indices, range) = expr,
                  ctx.sourceManager.origin(of: range.start.file) == .user
            else { return nil }
            return indices.first
        }
        #expect(indices.map { sema.bindings.exprType(for: $0) } == [sema.types.longType, sema.types.byteType, sema.types.uintType])
    }

    @Test
    func applicableMemberKeepsPriority() throws {
        let ctx = makeContextFromSource("""
        class Slots { operator fun get(index: Int): Int = index }
        operator fun Slots.get(index: Int): String = "extension"
        fun probe(slots: Slots): Int = slots[0]
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let callee = try indexedCallee(in: ctx)
        let owner = try #require(sema.symbols.parentSymbol(for: callee))
        #expect(sema.symbols.symbol(owner)?.name == ctx.interner.intern("Slots"))
    }

    @Test
    func inapplicableNearerExtensionDoesNotHideDefaultImport() throws {
        let ctx = makeContextFromSource("""
        operator fun Map<Char, Char>.get(key: String): Int = 1
        fun probe(map: Map<Char, Char>, key: Char?): Char? = map[key]
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let callee = try indexedCallee(in: ctx)
        #expect(sema.symbols.symbol(callee)?.fqName.map(ctx.interner.resolve) == ["kotlin", "collections", "get"])
    }

    @Test
    func invalidKeysAndExtensionsAreRejected() throws {
        let ctx = makeContextFromSource("""
        class MissingKey
        class ReceiverKey
        class NonOperatorKey
        class ArityKey
        class BoundKey
        operator fun List<String>.get(at: ReceiverKey): String = "wrong receiver"
        fun List<Int>.get(at: NonOperatorKey): Int = 1
        operator fun List<Int>.get(x: ArityKey, y: ArityKey): Int = 1
        operator fun <T : Number> List<T>.get(at: BoundKey): Int = 1
        fun wrongMapKey(map: Map<Char, Char>) = map[1]
        fun wrongMutableMapKey(map: MutableMap<Char, Char>) = map["wrong"]
        fun missingOperator(grid: List<List<Int>>) = grid[MissingKey()]
        fun wrongReceiver(grid: List<Int>) = grid[ReceiverKey()]
        fun nonOperator(grid: List<Int>) = grid[NonOperatorKey()]
        fun wrongArity(grid: List<Int>) = grid[ArityKey()]
        fun wrongBound(grid: List<String>) = grid[BoundKey()]
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError)
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        var rejected = 0
        for (index, expr) in ast.arena.exprs.enumerated() {
            guard case let .indexedAccess(_, _, range) = expr,
                  ctx.sourceManager.origin(of: range.start.file) == .user
            else { continue }
            #expect(sema.bindings.exprType(for: ExprID(rawValue: Int32(index))) == sema.types.errorType,
                    "Expected indexed access at \(range) to be rejected")
            rejected += 1
        }
        #expect(rejected == 7)
    }

    @Test
    func receiverWithoutGetIsNotTreatedAsAnArray() throws {
        let ctx = makeContextFromSource("""
        class Box<T>(val value: T)
        fun probe() {
            val scalar = 1
            scalar[0]
            val box = Box("value")
            box[0]
        }
        """)
        try runSema(ctx)

        let diagnostics = ctx.diagnostics.diagnostics
        #expect(diagnostics.filter { $0.code == "KSWIFTK-SEMA-0024" }.count == 2,
                "Expected unresolved get diagnostics: \(diagnostics)")
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let indexedAccesses = ast.arena.exprs.enumerated().compactMap { index, expr -> ExprID? in
            guard case let .indexedAccess(_, _, range) = expr,
                  ctx.sourceManager.origin(of: range.start.file) == .user
            else { return nil }
            return ExprID(rawValue: Int32(index))
        }
        #expect(indexedAccesses.count == 2)
        #expect(indexedAccesses.allSatisfy { sema.bindings.exprType(for: $0) == sema.types.errorType })
    }

    @Test(arguments: ["private", "public"])
    func extensionVisibilityIsPreserved(visibility: String) throws {
        let ctx = makeContextFromSources([
            """
            package operators
            class Slots { operator fun get(index: Int): Int = index }
            \(visibility) operator fun Slots.get(index: String): Int = 1
            """,
            """
            package consumer
            import operators.Slots
            import operators.get
            fun probe(slots: Slots): Int = slots["key"]
            """,
        ])
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError == (visibility == "private"), "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func ambiguousApplicableMembersAreNotReplacedByExtension() throws {
        let ctx = makeContextFromSource("""
        interface Left
        interface Right
        class Key : Left, Right
        class Slots {
            operator fun get(index: Left): Int = 1
            operator fun get(index: Right): Int = 2
        }
        operator fun Slots.get(index: Key): Int = 3
        fun probe(slots: Slots): Int = slots[Key()]
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0003" },
                "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func nullableMapKeyUsesProjectedExtension() throws {
        let ctx = makeContextFromSource("""
        fun main() {
            val relations = mapOf('(' to ')')
            val key: Char? = null
            println(relations[key])
            println(relations.get(key))
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test(arguments: [true, false])
    func nestedListExtensionInfersElement(generic: Bool) throws {
        let typeParameters = generic ? "<T> " : ""
        let element = generic ? "T" : "Int"
        let ctx = makeContextFromSource("""
        data class Point(val x: Int, val y: Int)
        operator fun \(typeParameters)List<List<\(element)>>.get(at: Point): \(element) = this[at.y][at.x]
        fun \(typeParameters)List<List<\(element)>>.at(at: Point): \(element) = this[at.y][at.x]
        fun main() {
            val grid = listOf(listOf(7))
            println(2 + grid[Point(0, 0)])
            println(2 + grid.get(Point(0, 0)))
            println(2 + grid.at(Point(0, 0)))
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    /// User overrides only inherit `operator` from the nearest overridden
    /// declaration, and bundled stdlib declarations keep exactly the modifiers
    /// they spell out, so `AbstractMutableList.get` must be an `operator` for
    /// `list[0]` on a subclass to resolve (it used to type as `Any`).
    @Test
    func abstractMutableListSubclassGetIsUsableThroughIndexSyntax() throws {
        let ctx = makeContextFromSource("""
        class Probe : AbstractMutableList<Int>() {
            override val size: Int get() = 1
            override fun get(index: Int): Int = 7
            override fun add(index: Int, element: Int) {}
            override fun removeAt(index: Int): Int = 0
            override fun set(index: Int, element: Int): Int = 0
        }
        fun read(probe: Probe): Int = probe[0]
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let callee = try indexedCallee(in: ctx)
        let owner = try #require(sema.symbols.parentSymbol(for: callee))
        #expect(sema.symbols.symbol(owner)?.name == ctx.interner.intern("Probe"))
    }

    private func indexedCallee(in ctx: CompilationContext) throws -> SymbolID {
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let indexed = try #require(firstExprID(in: ast) { _, expr in
            guard case let .indexedAccess(_, _, range) = expr else { return false }
            return ctx.sourceManager.origin(of: range.start.file) == .user
        })
        return try #require(sema.bindings.callBinding(for: indexed)?.chosenCallee)
    }
}
