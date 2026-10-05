#if canImport(Testing)
@testable import CompilerCore
import Testing

extension LoweringABIAndPropertyRegressionTests {
    @Test
    func testListViewChecksPreserveLegacyABIAndCatchContinuation() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()
        let receiver = arena.appendExpr(.temporary(0), type: types.nullableAnyType)
        let thrown = arena.appendExpr(.temporary(1), type: types.nullableAnyType)
        let forwardedThrown = arena.appendExpr(.temporary(2), type: types.nullableAnyType)
        let caller = KIRFunction(
            symbol: SymbolID(rawValue: 7900), name: interner.intern("main"), params: [],
            returnType: types.unitType,
            body: [
                .call(symbol: nil, callee: interner.intern("__kk_list_size"), arguments: [receiver],
                      result: nil, canThrow: false, thrownResult: thrown),
                .copy(from: thrown, to: forwardedThrown),
                .jumpIfNotNull(value: forwardedThrown, target: 1),
                .call(symbol: nil, callee: interner.intern("kk_list_iterator"), arguments: [receiver],
                      result: nil, canThrow: false, thrownResult: thrown),
                .jumpIfNotNull(value: thrown, target: 1),
                .label(1),
                .returnUnit,
            ],
            isSuspend: false, isInline: false
        )
        let id = arena.appendDecl(.function(caller))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [id])], arena: arena)
        try runLowering(module: module, interner: interner, moduleName: "ListViewChecks")
        let lowered = try findKIRFunction(named: "main", in: module, interner: interner)
        var checks = 0
        var legacyCalls = 0
        for (index, instruction) in lowered.body.enumerated() {
            guard case let .call(_, callee, args, _, canThrow, thrownResult, _, _) = instruction else { continue }
            switch interner.resolve(callee) {
            case "__kk_list_check_modification":
                checks += 1
                #expect(args == [receiver])
                #expect(canThrow && thrownResult == thrown)
                let continuation = lowered.body[(index + 1)...].prefix(2)
                #expect(continuation.contains {
                    if case .jumpIfNotNull(_, target: 1) = $0 { return true }
                    return false
                })
            case "__kk_list_size", "kk_list_iterator":
                legacyCalls += 1
                #expect(args == [receiver])
                #expect(!canThrow)
            default: break
            }
        }
        #expect(checks == 2)
        #expect(legacyCalls == 2)
    }

    @Test
    func testListViewChecksCoverCollectionArgumentsWithoutInstrumentingUnrelatedCalls() {
        let interner = StringInterner()
        let checks = ABILoweringPass().listViewCheckedArguments(interner: interner)
        #expect(checks[interner.intern("__kk_collection_size")] == [0])
        #expect(checks[interner.intern("__kk_mutable_list_addAll")] == [0, 1])
        #expect(checks[interner.intern("kk_range_iterator")] == [0])
        #expect(checks[interner.intern("__kk_map_size")] == nil)
        #expect(checks[interner.intern("__kk_list_check_modification")] == nil)
    }

    @Test
    func testListViewChecksRecognizeSourceBackedMembersButNotSameNamedUserMembers() {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let remove = interner.intern("remove")
        let stdlibMember = symbols.define(
            kind: .function, name: remove,
            fqName: ["kotlin", "collections", "MutableList", "remove"].map(interner.intern),
            declSite: nil, visibility: .public
        )
        let userMember = symbols.define(
            kind: .function, name: remove,
            fqName: ["example", "MutableList", "remove"].map(interner.intern),
            declSite: nil, visibility: .public
        )
        let members = ABILoweringPass().listViewMemberSymbols(symbols: symbols, interner: interner)
        #expect(members.contains(stdlibMember))
        #expect(!members.contains(userMember))
    }
}
#endif
