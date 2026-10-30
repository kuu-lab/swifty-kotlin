#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import TestStdlibCache
import Testing

@Suite
struct MemberExtensionStringIndicesTests {
    @Test(arguments: [false, true])
    func memberStringExtensionResolvesBareIndicesAndCountIt(useArtifact: Bool) throws {
        if useArtifact {
            TestStdlibCache.shared.prepare()
        }
        let ctx = makeContextFromSource("""
        class Solver {
            private infix fun String.diff(other: String): Int = indices.count { this[it] != other[it] }
            fun run(): Int = "abc" diff "axc"
        }

        private infix fun String.topLevelDiff(other: String): Int = indices.count { this[it] != other[it] }
        fun topLevelRun(): Int = "abc" topLevelDiff "axc"
        """, emit: useArtifact ? .executable : .kirDump, allowDefaultStdlibLibrary: useArtifact)
        try runSema(ctx)
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let sourcePath = try #require(ctx.options.inputs.first)
        let userErrors = ctx.diagnostics.diagnostics.filter { diagnostic in
            guard diagnostic.severity == .error,
                  let range = diagnostic.primaryRange
            else {
                return false
            }
            return ctx.sourceManager.path(of: range.start.file) == sourcePath
        }
        #expect(userErrors.isEmpty, "Unexpected diagnostics: \(userErrors)")

        func isUserSourceExpr(_ id: ExprID) -> Bool {
            guard let range = ast.arena.exprRange(id) else { return false }
            return ctx.sourceManager.path(of: range.start.file) == sourcePath
        }
        let itName = ctx.interner.intern("it")
        let itReferences = ast.arena.exprs.indices.compactMap { index -> ExprID? in
            let id = ExprID(rawValue: Int32(index))
            guard isUserSourceExpr(id),
                  case let .nameRef(name, _) = ast.arena.expr(id),
                  name == itName,
                  sema.bindings.exprType(for: id) != nil
            else {
                return nil
            }
            return id
        }
        #expect(itReferences.count == 4)
        let unresolvedItTypes = itReferences.compactMap { id -> String? in
            guard let type = sema.bindings.exprType(for: id) else { return "<unbound>" }
            return type == sema.types.intType
                ? nil
                : sema.types.displayName(of: type, symbols: sema.symbols, interner: ctx.interner)
        }
        #expect(unresolvedItTypes.isEmpty, "Expected Int for every it, got: \(unresolvedItTypes)")

        let indicesName = ctx.interner.intern("indices")
        let indicesReferences = ast.arena.exprs.indices.compactMap { index -> ExprID? in
            let id = ExprID(rawValue: Int32(index))
            guard isUserSourceExpr(id),
                  case let .nameRef(name, _) = ast.arena.expr(id),
                  name == indicesName,
                  sema.bindings.exprType(for: id) != nil
            else {
                return nil
            }
            return id
        }
        #expect(indicesReferences.count == 2)
        let indicesTypes = indicesReferences.map { id -> String in
            guard let type = sema.bindings.exprType(for: id) else { return "<unbound>" }
            return sema.types.displayName(of: type, symbols: sema.symbols, interner: ctx.interner)
        }
        #expect(indicesTypes == ["IntRange", "IntRange"], "indices types: \(indicesTypes)")
        #expect(indicesReferences.allSatisfy {
            sema.bindings.implicitReceiverMemberNames[$0] != nil
        })
        #expect(indicesReferences.allSatisfy {
            guard let symbol = sema.bindings.identifierSymbol(for: $0),
                  let receiver = sema.symbols.extensionPropertyReceiverType(for: symbol)
            else {
                return false
            }
            return sema.types.isSubtype(sema.types.stringType, receiver)
        })
    }
}
#endif
