#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// KSP-1122: the canonical `kotlin.concurrent.atomics.AtomicReference(T)`
/// constructor is represented by a source-backed factory that delegates to the
/// runtime-linked `kotlin.concurrent.AtomicReference` constructor.
@Suite(.serialized)
struct AtomicReferenceSourceMigrationTests {
    @Test
    func testAtomicReferenceConstructorIsSourceBackedAtCanonicalPackage() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)

        import kotlin.concurrent.atomics.AtomicReference

        fun makeBoxed(): AtomicReference<String> = AtomicReference("value")
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(
                errors.isEmpty,
                "Expected AtomicReference constructor source to type-check, got: \(errors.map { $0.code + ": " + $0.message })"
            )

            let sema = try #require(ctx.sema)
            let interner = ctx.interner
            let constructorFQName = ["kotlin", "concurrent", "atomics", "AtomicReference"].map(interner.intern)
            let underlyingFQName = ["kotlin", "concurrent", "AtomicReference"].map(interner.intern)
            let underlyingSymbol = try #require(sema.symbols.lookup(fqName: underlyingFQName))

            let factory = try #require(sema.symbols.lookupAll(fqName: constructorFQName).first { symbolID in
                guard let symbol = sema.symbols.symbol(symbolID),
                      symbol.kind == .function,
                      let signature = sema.symbols.functionSignature(for: symbolID),
                      signature.receiverType == nil,
                      signature.parameterTypes.count == 1,
                      signature.typeParameterSymbols.count == 1,
                      case let .typeParam(paramType) = sema.types.kind(of: signature.parameterTypes[0]),
                      paramType.symbol == signature.typeParameterSymbols[0],
                      case let .classType(returnType) = sema.types.kind(of: signature.returnType),
                      returnType.classSymbol == underlyingSymbol,
                      returnType.args.count == 1,
                      case let .invariant(returnArg) = returnType.args[0],
                      case let .typeParam(returnArgType) = sema.types.kind(of: returnArg),
                      returnArgType.symbol == signature.typeParameterSymbols[0]
                else {
                    return false
                }
                return true
            })

            let symbol = try #require(sema.symbols.symbol(factory))
            #expect(symbol.visibility == .public)
            #expect(!symbol.flags.contains(.synthetic))
            #expect(sema.symbols.isSourceBackedSymbol(factory))
            #expect(sema.symbols.externalLinkName(for: factory) == nil)
            let sourceFileID = try #require(sema.symbols.sourceFileID(for: factory))
            #expect(ctx.sourceManager.path(of: sourceFileID) == "__bundled_kotlin/concurrent/atomics/AtomicReference/Stdlib.kt")

            let annotations = sema.symbols.annotations(for: factory)
            #expect(
                annotations.contains { $0.annotationFQName == "kotlin.concurrent.atomics.ExperimentalAtomicApi" },
                "Expected ExperimentalAtomicApi annotation, got: \(annotations.map(\.annotationFQName))"
            )
            #expect(annotations.contains {
                $0.annotationFQName == "SinceKotlin"
                    && $0.arguments.contains(where: { $0.contains("2.1") })
            })

            let ast = try #require(ctx.ast)
            let call = try #require(ast.arena.exprs.indices.compactMap { index -> ExprID? in
                let exprID = ExprID(rawValue: Int32(index))
                guard let expr = ast.arena.expr(exprID),
                      case let .call(callee, _, _, range) = expr,
                      ctx.sourceManager.origin(of: range.start.file) == .user,
                      case let .nameRef(name, _) = ast.arena.expr(callee),
                      interner.resolve(name) == "AtomicReference"
                else {
                    return nil
                }
                return exprID
            }.first)
            #expect(sema.bindings.callBinding(for: call)?.chosenCallee == factory)
        }
    }
}
#endif
