#if canImport(Testing)
@testable import CompilerCore
import Testing
import TestStdlibCache
@testable import CompilerTestSupport

/// KUU-4345: the primitive member probe surfaces `kotlin`/`kotlin.ranges`/
/// `kotlin.text` package extensions as pseudo-members. A user-declared
/// extension in the current package is a nearer scope tier and must win
/// overload resolution over those default-import extensions.
@Suite
struct UserExtensionStdlibPriorityTests {
    private let userExtension = """
    package probe

    class BD

    fun Long.toBigDecimal(): BD = BD()

    fun useIt(x: Long): BD = x.toBigDecimal()
    """

    private let bundledOnly = """
    package probe

    fun useIt(x: Long) = x.toBigDecimal()
    """

    private let inapplicableUserExtension = """
    package probe

    fun Long.toBigDecimal(x: Int): String = "user"

    fun useIt(x: Long) = x.toBigDecimal()
    """

    /// KUU-4476: kotlin-result's zero-argument
    /// `Iterable<Result<V, E>>.partition()` shares its name with the bundled
    /// `partition(predicate)` collection HOF. The fast path must not claim
    /// the call — the result has to stay `Pair<List<V>, List<E>>`.
    private let userPartitionExtension = """
    package probe

    fun <V, E> Iterable<Pair<V, E>>.partition(): Pair<List<V>, List<E>> = Pair(listOf(), listOf())

    fun useIt(): Int {
        val (a, b) = listOf(1 to "x").partition()
        return a.size + b.size
    }
    """

    private func chosenCallees(
        named name: String,
        in ctx: CompilationContext
    ) throws -> [SemanticSymbol] {
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        var result: [SemanticSymbol] = []
        for index in ast.arena.exprs.indices {
            let call = ExprID(rawValue: Int32(index))
            let matches: Bool
            switch ast.arena.expr(call) {
            case let .call(callee, _, _, _):
                guard case let .nameRef(calleeName, _) = ast.arena.expr(callee) else {
                    continue
                }
                matches = ctx.interner.resolve(calleeName) == name
            case let .memberCall(_, calleeName, _, _, _):
                matches = ctx.interner.resolve(calleeName) == name
            default:
                continue
            }
            guard matches else { continue }
            let chosen = try #require(sema.bindings.callBinding(for: call)?.chosenCallee)
            result.append(try #require(sema.symbols.symbol(chosen)))
        }
        return result
    }

    @Test
    func userExtensionShadowsBundledStdlibExtension() throws {
        TestStdlibCache.shared.prepare()
        let ctx = makeContextFromSources(
            [userExtension],
            allowDefaultStdlibLibrary: true
        )
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "\(errors.map { "\($0.code): \($0.message)" })")

        let callees = try chosenCallees(named: "toBigDecimal", in: ctx)
        #expect(callees.count == 1)
        #expect(
            callees.first.map { $0.fqName.map { ctx.interner.resolve($0) } }
                == ["probe", "toBigDecimal"],
            "toBigDecimal resolved to \(callees.first?.fqName ?? [])"
        )
    }

    @Test
    func bundledStdlibExtensionStillResolvesWithoutUserDeclaration() throws {
        TestStdlibCache.shared.prepare()
        let ctx = makeContextFromSources(
            [bundledOnly],
            allowDefaultStdlibLibrary: true
        )
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "\(errors.map { "\($0.code): \($0.message)" })")

        let callees = try chosenCallees(named: "toBigDecimal", in: ctx)
        #expect(callees.count == 1)
        #expect(
            callees.first.map { $0.fqName.map { ctx.interner.resolve($0) } }
                == ["kotlin", "toBigDecimal"],
            "toBigDecimal resolved to \(callees.first?.fqName ?? [])"
        )
    }

    /// kotlinc keeps resolving lower tiers when the nearer declaration is
    /// inapplicable to the call, so an arity-mismatched user extension must
    /// not hide the bundled `kotlin.Long.toBigDecimal()`.
    @Test
    func inapplicableUserExtensionDoesNotShadowBundledStdlibExtension() throws {
        TestStdlibCache.shared.prepare()
        let ctx = makeContextFromSources(
            [inapplicableUserExtension],
            allowDefaultStdlibLibrary: true
        )
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "\(errors.map { "\($0.code): \($0.message)" })")

        let callees = try chosenCallees(named: "toBigDecimal", in: ctx)
        #expect(callees.count == 1)
        #expect(
            callees.first.map { $0.fqName.map { ctx.interner.resolve($0) } }
                == ["kotlin", "toBigDecimal"],
            "toBigDecimal resolved to \(callees.first?.fqName ?? [])"
        )
    }

    /// The collection-HOF fast path models only the bundled
    /// `partition(predicate)` shape; a user-declared zero-argument
    /// `partition` extension must reach regular overload resolution so the
    /// call keeps its real `Pair` result type instead of degrading to Any
    /// (KUU-4476).
    @Test
    func userPartitionExtensionKeepsPairResultType() throws {
        TestStdlibCache.shared.prepare()
        let ctx = makeContextFromSources(
            [userPartitionExtension],
            allowDefaultStdlibLibrary: true
        )
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "\(errors.map { "\($0.code): \($0.message)" })")

        let callees = try chosenCallees(named: "partition", in: ctx)
        #expect(callees.count == 1)
        #expect(
            callees.first.map { $0.fqName.map { ctx.interner.resolve($0) } }
                == ["probe", "partition"],
            "partition resolved to \(callees.first?.fqName ?? [])"
        )
    }
}
#endif
