#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct ExternalObjectPropertyLoweringTests {
    @Test(arguments: [SymbolKind.package, .object], [false, true])
    func externalGetterUsesOwnerReceiverOnlyForObjects(ownerKind: SymbolKind, symbolReference: Bool) throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()
        let symbols = SymbolTable()
        let ownerName = interner.intern("Owner")
        let owner = symbols.define(
            kind: ownerKind, name: ownerName, fqName: [ownerName],
            declSite: nil, visibility: .public, flags: [.synthetic]
        )
        let name = interner.intern("value")
        let property = symbols.define(
            kind: .property, name: name, fqName: [ownerName, name],
            declSite: nil, visibility: .public, flags: [.synthetic]
        )
        symbols.setParentSymbol(owner, for: property)
        symbols.setPropertyType(types.intType, for: property)
        symbols.setExternalLinkName("external_value", for: property)
        let result = arena.appendTemporary(type: types.intType)
        let function = KIRFunction(
            symbol: SymbolID(rawValue: 100), name: interner.intern("caller"),
            params: [], returnType: types.intType,
            body: [
                symbolReference ? .constValue(result: result, value: .symbolRef(property))
                    : .loadGlobal(result: result, symbol: property),
                .returnValue(result),
            ], isSuspend: false, isInline: false
        )
        let id = arena.appendDecl(.function(function))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [id])], arena: arena)
        let sema = makeSemaModule(symbols: symbols, types: types).ctx
        try PropertyLoweringPass().run(module: module, ctx: makeKIRContext(interner: interner, sema: sema))
        let lowered = try #require(arena.decl(id)?.function)
        let calls = loweringCalls(in: lowered.body)
        let call = try #require(calls.first)
        #expect(calls.count == 1)
        #expect(interner.resolve(call.callee) == "external_value")
        #expect(call.result == result)
        #expect(call.arguments.count == (ownerKind == .object ? 1 : 0))
        if ownerKind == .object {
            let receiver = try #require(call.arguments.first)
            #expect(arena.expr(receiver) == .symbolRef(owner))
            #expect(lowered.body.contains(.constValue(result: receiver, value: .symbolRef(owner))))
        }
    }
}
#endif
