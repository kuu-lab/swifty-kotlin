#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// KSP-1112: the canonical `kotlin.concurrent.atomics.AtomicInt(Int)`
/// constructor is represented by a source-backed factory linked directly to
/// the runtime allocation for the canonical nominal type.
@Suite(.serialized)
struct AtomicIntSourceMigrationTests {
    @Test
    func testAtomicIntConstructorIsSourceBackedAtCanonicalPackage() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)

        import kotlin.concurrent.atomics.AtomicInt

        fun makeCounter(): AtomicInt = AtomicInt(1)
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(
                errors.isEmpty,
                "Expected AtomicInt constructor source to type-check, got: \(errors.map { $0.code + ": " + $0.message })"
            )

            let sema = try #require(ctx.sema)
            let interner = ctx.interner
            let constructorFQName = ["kotlin", "concurrent", "atomics", "AtomicInt"].map(interner.intern)
            let canonicalSymbol = try #require(sema.symbols.lookup(fqName: constructorFQName))
            let expectedReturn = sema.types.make(.classType(ClassType(
                classSymbol: canonicalSymbol,
                args: [],
                nullability: .nonNull
            )))

            let factory = try #require(sema.symbols.lookupAll(fqName: constructorFQName).first { symbolID in
                guard let symbol = sema.symbols.symbol(symbolID),
                      symbol.kind == .function,
                      let signature = sema.symbols.functionSignature(for: symbolID)
                else {
                    return false
                }
                return signature.receiverType == nil
                    && signature.parameterTypes == [sema.types.intType]
                    && signature.returnType == expectedReturn
            })

            let symbol = try #require(sema.symbols.symbol(factory))
            #expect(symbol.visibility == .public)
            #expect(!symbol.flags.contains(.synthetic))
            #expect(sema.symbols.isSourceBackedSymbol(factory))
            #expect(sema.symbols.externalLinkName(for: factory) == runtimeABIName(.atomicIntCreate))
            let sourceFileID = try #require(sema.symbols.sourceFileID(for: factory))
            #expect(ctx.sourceManager.path(of: sourceFileID) == "__bundled_kotlin/concurrent/atomics/AtomicInt/Stdlib.kt")

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
            let call = try #require(ast.arena.exprs.indices.compactMap { index -> ExprID? in
                let exprID = ExprID(rawValue: Int32(index))
                guard let expr = ast.arena.expr(exprID),
                      case let .call(callee, _, _, range) = expr,
                      ctx.sourceManager.origin(of: range.start.file) == .user,
                      case let .nameRef(name, _) = ast.arena.expr(callee),
                      interner.resolve(name) == "AtomicInt"
                else {
                    return nil
                }
                return exprID
            }.first)
            #expect(sema.bindings.callBinding(for: call)?.chosenCallee == factory)
        }
    }
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
        #expect(sema.symbols.externalLinkName(for: factory) == runtimeABIName(.atomicIntCreate))

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
