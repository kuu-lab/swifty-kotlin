#if canImport(Testing)
@testable import CompilerCore
import Testing

/// KSP-1114: the canonical AtomicIntArray constructors are source-backed while
/// the residual nominal shell and array operations keep their runtime ABI.
@Suite(.serialized)
struct AtomicIntArrayCanonicalSourceMigrationTests {
    @Test
    func testConstructorsArePublicSourceBackedAtCanonicalPackage() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)

        import kotlin.concurrent.atomics.AtomicIntArray

        fun fromSize(size: Int): AtomicIntArray = AtomicIntArray(size)
        fun fromArray(values: IntArray): AtomicIntArray = AtomicIntArray(values)
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(
                errors.isEmpty,
                "Expected canonical AtomicIntArray constructors to type-check, got: \(errors.map { $0.code + ": " + $0.message })"
            )

            let sema = try #require(ctx.sema)
            let interner = ctx.interner
            let constructorFQName = ["kotlin", "concurrent", "atomics", "AtomicIntArray"].map(interner.intern)
            let arraySymbol = try #require(sema.symbols.lookup(fqName: constructorFQName))
            let arrayType = sema.types.make(.classType(ClassType(
                classSymbol: arraySymbol,
                args: [],
                nullability: .nonNull
            )))
            let intArraySymbol = try #require(
                sema.symbols.lookup(fqName: ["kotlin", "IntArray"].map(interner.intern))
            )
            let intArrayType = sema.types.make(.classType(ClassType(
                classSymbol: intArraySymbol,
                args: [],
                nullability: .nonNull
            )))

            let constructors = sema.symbols.lookupAll(fqName: constructorFQName).filter { candidate in
                guard let symbol = sema.symbols.symbol(candidate),
                      symbol.kind == .function,
                      let signature = sema.symbols.functionSignature(for: candidate)
                else {
                    return false
                }
                return signature.receiverType == nil && signature.returnType == arrayType
            }
            let sizeConstructor = try #require(constructors.first { candidate in
                sema.symbols.functionSignature(for: candidate)?.parameterTypes == [sema.types.intType]
            })
            let arrayConstructor = try #require(constructors.first { candidate in
                sema.symbols.functionSignature(for: candidate)?.parameterTypes == [intArrayType]
            })

            let sizeInfo = try #require(sema.symbols.symbol(sizeConstructor))
            #expect(sizeInfo.visibility == .public)
            #expect(!sizeInfo.flags.contains(.synthetic))
            #expect(sema.symbols.isSourceBackedSymbol(sizeConstructor))
            #expect(sema.symbols.externalLinkName(for: sizeConstructor) == "kk_atomic_int_array_create")

            let arrayInfo = try #require(sema.symbols.symbol(arrayConstructor))
            #expect(arrayInfo.visibility == .public)
            #expect(!arrayInfo.flags.contains(.synthetic))
            #expect(sema.symbols.isSourceBackedSymbol(arrayConstructor))
            #expect(sema.symbols.externalLinkName(for: arrayConstructor) == nil)

            let sourceFileID = try #require(sema.symbols.sourceFileID(for: sizeConstructor))
            #expect(ctx.sourceManager.path(of: sourceFileID) == "__bundled_kotlin/concurrent/atomics/AtomicIntArray/Stdlib.kt")
            #expect(sema.symbols.sourceFileID(for: arrayConstructor) == sourceFileID)

            let ast = try #require(ctx.ast)
            let calls = ast.arena.exprs.indices.compactMap { index -> ExprID? in
                let exprID = ExprID(rawValue: Int32(index))
                guard let expr = ast.arena.expr(exprID),
                      case let .call(callee, _, _, range) = expr,
                      ctx.sourceManager.origin(of: range.start.file) == .user,
                      case let .nameRef(name, _) = ast.arena.expr(callee),
                      interner.resolve(name) == "AtomicIntArray"
                else {
                    return nil
                }
                return exprID
            }
            #expect(calls.count == 2)

            let chosenCallees = try calls.map { call in
                try #require(sema.bindings.callBinding(for: call)?.chosenCallee)
            }
            #expect(chosenCallees.contains(sizeConstructor))
            #expect(chosenCallees.contains(arrayConstructor))
            #expect(chosenCallees.allSatisfy { sema.symbols.isSourceBackedSymbol($0) })
            #expect(calls.allSatisfy { sema.bindings.stdlibSpecialCallKind(for: $0) == nil })
        }
    }
}
#endif
