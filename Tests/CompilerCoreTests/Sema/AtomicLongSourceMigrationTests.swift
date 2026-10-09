#if canImport(Testing)
@testable import CompilerCore
import Testing

/// KSP-1091: the legacy `kotlin.concurrent.AtomicLong(Long)` constructor
/// surface is a source-backed factory entry point while the residual synthetic
/// constructor keeps its runtime ABI link for the remaining atomic surfaces.
/// KSP-1116: the canonical `kotlin.concurrent.atomics.AtomicLong(Long)`
/// constructor is a source-backed factory delegating to the same allocation.
@Suite(.serialized)
struct AtomicLongSourceMigrationTests {
    @Test
    func testConstructorIsSourceBackedAndKeepsTheRuntimeLink() throws {
        let ctx = makeContextFromSource("""
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
        @file:Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")

        import kotlin.concurrent.AtomicLong

        fun fromValue(value: Long): AtomicLong = AtomicLong(value)
        """)
        try runSema(ctx)

        #expect(
            !ctx.diagnostics.hasError,
            "Expected AtomicLong constructor source to type-check, got: \(ctx.diagnostics.diagnostics)"
        )

        let sema = try #require(ctx.sema)
        let interner = ctx.interner
        let constructorFQName = ["kotlin", "concurrent", "AtomicLong"].map(interner.intern)
        let classSymbol = try #require(sema.symbols.lookup(fqName: constructorFQName))
        let atomicLongType = sema.types.make(.classType(ClassType(
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
                && signature.parameterTypes == [sema.types.longType]
                && signature.returnType == atomicLongType
        })
        let factoryInfo = try #require(sema.symbols.symbol(factory))
        #expect(factoryInfo.visibility == .public)
        #expect(!factoryInfo.flags.contains(.synthetic))
        #expect(sema.symbols.isSourceBackedSymbol(factory))
        #expect(sema.symbols.externalLinkName(for: factory) == runtimeABIName(.atomicLongCreate))

        let sourceFileID = try #require(sema.symbols.sourceFileID(for: factory))
        #expect(ctx.sourceManager.path(of: sourceFileID) == "__bundled_kotlin/concurrent/AtomicLong/Stdlib.kt")

        let ast = try #require(ctx.ast)
        let calls = ast.arena.exprs.indices.compactMap { index -> ExprID? in
            let exprID = ExprID(rawValue: Int32(index))
            guard case let .call(callee, _, _, range) = ast.arena.expr(exprID),
                  ctx.sourceManager.origin(of: range.start.file) == .user,
                  case let .nameRef(name, _) = ast.arena.expr(callee),
                  interner.resolve(name) == "AtomicLong"
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

    @Test
    func testAtomicLongConstructorIsSourceBackedAtCanonicalPackage() throws {
        let ctx = makeContextFromSource("""
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)

        import kotlin.concurrent.atomics.AtomicLong

        fun makeCounter(): AtomicLong = AtomicLong(1L)
        """)
        try runSema(ctx)

        #expect(
            !ctx.diagnostics.hasError,
            "Expected AtomicLong constructor source to type-check, got: \(ctx.diagnostics.diagnostics)"
        )

        let sema = try #require(ctx.sema)
        let interner = ctx.interner
        let constructorFQName = ["kotlin", "concurrent", "atomics", "AtomicLong"].map(interner.intern)
        let underlyingSymbol = try #require(sema.symbols.lookupAll(fqName: constructorFQName).first { candidate in
            sema.symbols.symbol(candidate)?.kind == .class
        })
        let expectedReturn = sema.types.make(.classType(ClassType(
            classSymbol: underlyingSymbol,
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
                && signature.parameterTypes == [sema.types.longType]
                && signature.returnType == expectedReturn
        })

        let factoryInfo = try #require(sema.symbols.symbol(factory))
        #expect(factoryInfo.visibility == .public)
        #expect(!factoryInfo.flags.contains(.synthetic))
        #expect(sema.symbols.isSourceBackedSymbol(factory))
        #expect(sema.symbols.externalLinkName(for: factory) == runtimeABIName(.atomicLongCreate))
        let sourceFileID = try #require(sema.symbols.sourceFileID(for: factory))
        #expect(ctx.sourceManager.path(of: sourceFileID) == "__bundled_kotlin/concurrent/atomics/AtomicLong/Stdlib.kt")

        let annotations = sema.symbols.annotations(for: factory)
        #expect(
            annotations.contains { $0.annotationFQName == "kotlin.concurrent.atomics.ExperimentalAtomicApi" },
            "Expected ExperimentalAtomicApi annotation, got: \(annotations.map(\.annotationFQName))"
        )
        #expect(annotations.contains {
            $0.annotationFQName == "kotlin.SinceKotlin"
                && $0.arguments.contains(where: { $0.contains("2.1") })
        })

        let ast = try #require(ctx.ast)
        let calls = ast.arena.exprs.indices.compactMap { index -> ExprID? in
            let exprID = ExprID(rawValue: Int32(index))
            guard case let .call(callee, _, _, range) = ast.arena.expr(exprID),
                  ctx.sourceManager.origin(of: range.start.file) == .user,
                  case let .nameRef(name, _) = ast.arena.expr(callee),
                  interner.resolve(name) == "AtomicLong"
            else {
                return nil
            }
            return exprID
        }
        #expect(calls.count == 1)
        #expect(calls.allSatisfy { sema.bindings.callBinding(for: $0)?.chosenCallee == factory })
    }
}
#endif
