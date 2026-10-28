#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct ImportedObjectPropertyAssignmentTests {
    @Test
    func importedObjectPropertySupportsBareReadAndWrite() throws {
        let ctx = makeContextFromSource("""
        import C.p
        object C { var p: Int = 0 }
        fun read(): Int = p
        fun write() { p = 1 }
        fun qualifiedWrite() { C.p = 2 }
        """)
        try runToKIR(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Unexpected error diagnostics: \(errors.map(\.code))")
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let module = try #require(ctx.kir)
        let property = try #require(sema.symbols.lookup(fqName: ["C", "p"].map(ctx.interner.intern)))
        let assignment = try #require(firstExprID(in: ast) { _, expr in
            guard case let .localAssign(name, _, _) = expr else { return false }
            return name == ctx.interner.intern("p")
        })
        let writeBody = try findKIRFunctionBody(named: "write", in: module, interner: ctx.interner)
        let objectInitGuardIndex = try #require(writeBody.firstIndex { instruction in
            if case let .call(_, callee, _, _, _, _, _, _) = instruction {
                return ctx.interner.resolve(callee).hasPrefix("__object_lazy_init_")
            }
            return false
        })
        let propertyWriteIndex = try #require(writeBody.firstIndex { instruction in
            if case let .copy(_, to) = instruction {
                return module.arena.expr(to) == .symbolRef(property)
            }
            return false
        })

        #expect(sema.bindings.identifierSymbol(for: assignment) == property)
        #expect(objectInitGuardIndex < propertyWriteIndex)
    }

    @Test
    func aliasedImportedObjectPropertyUsesItsSingletonSetterReceiver() throws {
        let ctx = makeContextFromSource("""
        import D.q as aliasQ
        object D {
            var q: Int = 0
                set(value) { field = value * 2 }
        }
        fun writeAlias() { aliasQ = 1 }
        fun readAlias(): Int = aliasQ
        fun readQualified(): Int = D.q
        """)
        try runToKIR(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Unexpected error diagnostics: \(errors.map(\.code))")
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let module = try #require(ctx.kir)
        let property = try #require(sema.symbols.lookup(fqName: ["D", "q"].map(ctx.interner.intern)))
        let backingField = try #require(sema.symbols.backingFieldSymbol(for: property))
        let owner = try #require(sema.symbols.parentSymbol(for: property))
        let assignment = try #require(firstExprID(in: ast) { _, expr in
            guard case let .localAssign(name, _, _) = expr else { return false }
            return name == ctx.interner.intern("aliasQ")
        })
        let setter = sema.symbols.extensionPropertySetterAccessor(for: property)
            ?? SyntheticSymbolScheme.propertySetterAccessorSymbol(for: property)
        let body = try findKIRFunctionBody(named: "writeAlias", in: module, interner: ctx.interner)
        let aliasReadBody = try findKIRFunctionBody(named: "readAlias", in: module, interner: ctx.interner)
        let qualifiedReadBody = try findKIRFunctionBody(named: "readQualified", in: module, interner: ctx.interner)
        let setterCalls = body.compactMap { instruction -> [KIRExprID]? in
            guard case let .call(symbol, _, arguments, _, _, _, _, _) = instruction,
                  symbol == setter else { return nil }
            return arguments
        }

        #expect(sema.bindings.identifierSymbol(for: assignment) == property)
        #expect(setterCalls.count == 1)
        #expect(setterCalls.first?.count == 2)
        #expect(aliasReadBody.contains {
            if case let .loadGlobal(_, symbol) = $0 { return symbol == backingField }
            return false
        })
        #expect(qualifiedReadBody.contains {
            if case let .loadGlobal(_, symbol) = $0 { return symbol == backingField }
            return false
        })
        if let receiver = setterCalls.first?.first {
            #expect(module.arena.expr(receiver) == .symbolRef(owner))
        }
    }

    @Test
    func unimportedInstancePropertyIsNotBareAssignable() throws {
        let ctx = makeContextFromSource("""
        class Box { var p: Int = 0 }
        fun write() { p = 1 }
        """)
        try runSema(ctx)

        #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0013" })
    }
}
#endif
