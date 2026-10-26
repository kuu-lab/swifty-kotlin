@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct ListReduceApplicabilityTests {
    private static func reduceCalls(in ast: ASTModule, interner: StringInterner, userFileID: FileID) -> [ExprID] {
        ast.arena.exprs.indices.compactMap { index in
            let id = ExprID(rawValue: Int32(index))
            let callee: InternedString? = switch ast.arena.expr(id) {
            case let .memberCall(_, name, _, _, _), let .safeMemberCall(_, name, _, _, _): name
            default: nil
            }
            guard let callee, interner.resolve(callee) == "reduce",
                  ast.arena.exprRange(id)?.start.file == userFileID
            else {
                return nil
            }
            return id
        }
    }

    private static let declarations = """
    package fixture
    open class Base
    class Leaf : Base()
    fun Base.combine(other: Base): Base = this
    """

    @Test
    func distinctAccumulatorAndElementTypesBindCanonicalDeclaration() throws {
        let ctx = makeContextFromSource(Self.declarations + """

        fun inferred(values: List<Leaf>): Base = values.reduce<Base, Leaf> { acc, item -> item.combine(acc) }
        fun explicit(values: List<Leaf>): Base = values.reduce<Base, Leaf> { acc: Base, item: Leaf -> item.combine(acc) }
        fun iterable(values: Iterable<Leaf>): Base = values.reduce<Base, Leaf> { acc, item -> item.combine(acc) }
        fun direct(item: Leaf, acc: Base): Base = item.combine(acc)
        fun homogeneous(values: List<Leaf>): Leaf = values.reduce<Leaf, Leaf> { _, item -> item }
        fun unannotated(values: List<Leaf>): Leaf = values.reduce { _, item -> item }
        fun implicit(values: List<Leaf>): Base = values.reduce { acc: Base, item: Leaf -> item.combine(acc) }
        fun mutable(values: MutableList<Leaf>): Base = values.reduce<Base, Leaf> { acc, item -> item.combine(acc) }
        fun nullable(values: List<Leaf>?): Base? = values?.reduce<Base, Leaf> { acc, item -> item.combine(acc) }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let userFileID = try #require(ctx.sourceManager.fileIDs().first {
            ctx.sourceManager.origin(of: $0) == .user
        })
        let calls = Self.reduceCalls(in: ast, interner: ctx.interner, userFileID: userFileID)
        #expect(calls.count == 8)
        for call in calls {
            let binding = try #require(sema.bindings.callBinding(for: call))
            #expect(sema.symbols.isSourceBackedSymbol(binding.chosenCallee))
            let signature = try #require(sema.symbols.functionSignature(for: binding.chosenCallee))
            #expect(signature.typeParameterSymbols.count == 2)
            let receiver = try #require(signature.receiverType)
            guard case let .classType(type) = sema.types.kind(of: receiver) else {
                Issue.record("Expected the canonical Iterable receiver")
                continue
            }
            let symbol = try #require(sema.symbols.symbol(type.classSymbol))
            #expect(symbol.fqName.map(ctx.interner.resolve).joined(separator: ".") == "kotlin.collections.Iterable")
        }
    }

    @Test(arguments: [
        "fun result(values: List<Leaf>): Leaf = values.reduce<Leaf> { _, item -> item }",
        "fun result(values: List<Leaf>): Leaf = values.reduce<Leaf, Leaf, Leaf> { _, item -> item }",
        "class Foreign; fun result(values: List<Foreign>): Base = values.reduce<Base, Foreign> { acc, _ -> acc }",
        "class Foreign; fun result(values: Iterable<Foreign>): Base = values.reduce<Base, Foreign> { acc, _ -> acc }",
        "fun result(values: List<Leaf>): Leaf = values.reduce()",
        "fun result(values: List<Leaf>): Leaf = values.reduce({ a: Leaf, b: Leaf -> b }, { a: Leaf, b: Leaf -> b })",
        "fun result(values: List<Leaf>): Leaf = values.reduce<Leaf, Leaf>(missing = { a: Leaf, b: Leaf -> b })",
        "fun result(values: List<Leaf>): Leaf = values.reduce<Leaf, Leaf> { acc, item -> Base() }",
        "fun result(values: List<Leaf>): Base = values.reduce { acc, item -> item.combine(acc) }",
        "fun result(values: List<Leaf>): Leaf = values.reduce(*{ _, item -> item })",
    ])
    func invalidCallsAreRejected(source: String) throws {
        let ctx = makeContextFromSource(Self.declarations + "\n" + source)
        try runSema(ctx)
        #expect(ctx.diagnostics.diagnostics.contains {
            $0.severity == .error && ($0.code.hasPrefix("KSWIFTK-SEMA-") || $0.code.hasPrefix("KSWIFTK-TYPE-"))
        }, "Expected reduce applicability rejection: \(ctx.diagnostics.diagnostics)")
    }

    @Test
    func unrelatedZeroArgumentExtensionPreservesDefaultLambdaContext() throws {
        let ctx = makeContextFromSource("""
        package fixture
        fun List<Int>.reduce(): String = "user"
        fun result(values: List<Int>): Int = values.reduce { acc, item -> acc + item }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let userFileID = try #require(ctx.sourceManager.fileIDs().first {
            ctx.sourceManager.origin(of: $0) == .user
        })
        let calls = Self.reduceCalls(in: ast, interner: ctx.interner, userFileID: userFileID)
        #expect(calls.count == 1)
        let call = try #require(calls.first)
        let binding = try #require(sema.bindings.callBinding(for: call))
        let signature = try #require(sema.symbols.functionSignature(for: binding.chosenCallee))
        #expect(signature.typeParameterSymbols.count == 2)
        #expect(sema.symbols.isSourceBackedSymbol(binding.chosenCallee))
    }

    @Test
    func userExtensionWithOneTypeParameterRemainsApplicable() throws {
        let ctx = makeContextFromSource("""
        package fixture
        fun <T> List<T>.reduce(operation: (T, T) -> T): T = this[0]
        fun result(values: List<Int>): Int = values.reduce<Int> { acc, item -> acc + item }
        fun implicit(values: List<Int>): Int = values.reduce { acc, item -> acc + item }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let userFileID = try #require(ctx.sourceManager.fileIDs().first {
            ctx.sourceManager.origin(of: $0) == .user
        })
        let calls = Self.reduceCalls(in: ast, interner: ctx.interner, userFileID: userFileID)
        #expect(calls.count == 2)
        for call in calls {
            let binding = try #require(sema.bindings.callBinding(for: call))
            #expect(sema.symbols.sourceFileID(for: binding.chosenCallee) == userFileID)
        }
    }

    @Test
    func inaccessibleUserExtensionDoesNotBypassTypeArity() throws {
        let ctx = makeContextFromSources([
            "package fixture; private fun <T> List<T>.reduce(operation: (T, T) -> T): T = this[0]",
            "package fixture; fun result(values: List<Int>): Int = values.reduce<Int> { acc, item -> acc + item }",
        ])
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError)
    }
}
