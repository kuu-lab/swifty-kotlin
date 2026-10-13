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
                .call(symbol: nil, callee: interner.intern(try loweringRuntimeABI("list_size").name), arguments: [receiver],
                      result: nil, canThrow: false, thrownResult: thrown),
                .copy(from: thrown, to: forwardedThrown),
                .jumpIfNotNull(value: forwardedThrown, target: 1),
                .call(symbol: nil, callee: interner.intern(try loweringRuntimeABI("list_iterator").name), arguments: [receiver],
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
        let checkCallee = interner.intern(try loweringRuntimeABI("list_check_modification").name)
        let sizeCallee = interner.intern(try loweringRuntimeABI("list_size").name)
        let iteratorCallee = interner.intern(try loweringRuntimeABI("list_iterator").name)
        var checks = 0
        var legacyCalls = 0
        for (index, instruction) in lowered.body.enumerated() {
            guard case let .call(_, callee, args, _, canThrow, thrownResult, _, _) = instruction else { continue }
            switch callee {
            case checkCallee:
                checks += 1
                #expect(args == [receiver])
                #expect(canThrow && thrownResult == thrown)
                let continuation = lowered.body[(index + 1)...].prefix(2)
                #expect(continuation.contains {
                    if case .jumpIfNotNull(_, target: 1) = $0 { return true }
                    return false
                })
            case sizeCallee, iteratorCallee:
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
    func testListViewChecksCoverCollectionArgumentsWithoutInstrumentingUnrelatedCalls() throws {
        let interner = StringInterner()
        let checks = ABILoweringPass().listViewCheckedArguments(interner: interner)
        #expect(checks[interner.intern(try loweringRuntimeABI("collection_size").name)] == [0])
        #expect(checks[interner.intern(try loweringRuntimeABI("mutable_list_addAll").name)] == [0, 1])
        #expect(checks[interner.intern(try loweringRuntimeABI("range_iterator").name)] == [0])
        #expect(checks[interner.intern(try loweringRuntimeABI("map_size").name)] == nil)
        #expect(checks[interner.intern(try loweringRuntimeABI("list_check_modification").name)] == nil)
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
