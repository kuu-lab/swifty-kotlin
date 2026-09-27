#if canImport(Testing)
@testable import CompilerCore
import Testing

/// KSP-1087: the legacy `kotlin.concurrent.AtomicInt(Int)` constructor surface
/// is a source-backed factory entry point while the residual synthetic
/// constructor keeps its runtime ABI link for `AtomicInteger` compatibility.
@Suite(.serialized)
struct AtomicIntSourceMigrationTests {
    @Test
    func testConstructorIsSourceBackedAndKeepsTheRuntimeLink() throws {
        let ctx = makeContextFromSource("""
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        @file:Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")

        import kotlin.concurrent.AtomicInt

        fun fromValue(value: Int): AtomicInt = AtomicInt(value)
        """)
        try runSema(ctx)

        #expect(
            !ctx.diagnostics.hasError,
            "Expected AtomicInt constructor source to type-check, got: \(ctx.diagnostics.diagnostics)"
        )

        let sema = try #require(ctx.sema)
        let interner = ctx.interner
        let constructorFQName = ["kotlin", "concurrent", "AtomicInt"].map(interner.intern)
        let classSymbol = try #require(sema.symbols.lookup(fqName: constructorFQName))
        let atomicIntType = sema.types.make(.classType(ClassType(
            classSymbol: classSymbol,
            args: [],
            nullability: .nonNull
        )))

        let factory = try #require(sema.symbols.lookupAll(fqName: constructorFQName).first { candidate in
            guard let symbol = sema.symbols.symbol(candidate),
                  symbol.kind == .function,
                  let signature = sema.symbols.functionSignature(for: candidate)
            else {
                return false
            }
            return signature.receiverType == nil
                && signature.parameterTypes == [sema.types.intType]
                && signature.returnType == atomicIntType
        })
        let factoryInfo = try #require(sema.symbols.symbol(factory))
        #expect(factoryInfo.visibility == .public)
        #expect(!factoryInfo.flags.contains(.synthetic))
        #expect(sema.symbols.isSourceBackedSymbol(factory))
        #expect(sema.symbols.externalLinkName(for: factory) == "kk_atomic_int_create")

        let sourceFileID = try #require(sema.symbols.sourceFileID(for: factory))
        #expect(ctx.sourceManager.path(of: sourceFileID) == "__bundled_kotlin/concurrent/AtomicInt/Stdlib.kt")

        let ast = try #require(ctx.ast)
        let calls = ast.arena.exprs.indices.compactMap { index -> ExprID? in
            let exprID = ExprID(rawValue: Int32(index))
            guard case let .call(callee, _, _, range) = ast.arena.expr(exprID),
                  ctx.sourceManager.origin(of: range.start.file) == .user,
                  case let .nameRef(name, _) = ast.arena.expr(callee),
                  interner.resolve(name) == "AtomicInt"
            else {
                return nil
            }
            return exprID
        }
        #expect(calls.count == 1)

        let chosenCallee = try #require(calls.first.flatMap { sema.bindings.callBinding(for: $0)?.chosenCallee })
        #expect(chosenCallee == factory)
        #expect(sema.symbols.isSourceBackedSymbol(chosenCallee))
        #expect(calls.allSatisfy { sema.bindings.stdlibSpecialCallKind(for: $0) == nil })
    }
}
#endif
