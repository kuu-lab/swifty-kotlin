@testable import CompilerCore
import Testing

@Suite
struct MutexContinuationLoweringTests {
    @Test(arguments: [false, true], [false, true])
    func lockContinuationPreservesABI(owner: Bool, suspend: Bool) throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()
        let handle = arena.appendExpr(.intLiteral(10), type: types.intType)
        let ownerToken = arena.appendExpr(.intLiteral(20), type: types.nullableAnyType)
        let placeholder = arena.appendExpr(.intLiteral(0), type: types.intType)
        let thrown = arena.appendTemporary(type: types.nullableAnyType)
        let callee = interner.intern(owner ? "__kk_mutex_lock_owner" : "kk_mutex_lock")
        let arguments = (owner ? [handle, ownerToken] : [handle]) + [placeholder]
        let function = KIRFunction(
            symbol: SymbolID(rawValue: 1), name: interner.intern("waitForMutex"),
            params: [], returnType: types.unitType,
            body: [
                .call(callee: callee, arguments: arguments,
                      result: nil, canThrow: owner, thrownResult: owner ? thrown : nil),
                .returnUnit,
            ],
            isSuspend: suspend, isInline: false
        )
        let declaration = arena.appendDecl(.function(function))
        let module = KIRModule(files: [], arena: arena)
        try CoroutineLoweringPass().run(module: module, ctx: makeKIRContext(interner: interner))
        let functions = arena.declarations.compactMap { $0.function }
        let lowered = try #require(suspend ? functions.first { function in
            function.body.contains { instruction in
                guard case let .call(_, name, _, _, _, _, _, _) = instruction else { return false }
                return interner.resolve(name) == "kk_coroutine_state_enter"
            }
        } : arena.decl(declaration)?.function)
        let call = try #require(lowered.body.first { instruction in
            guard case let .call(_, name, _, _, _, _, _, _) = instruction else { return false }
            return name == callee
        })
        guard case let .call(_, _, actual, _, canThrow, thrownResult, _, _) = call else {
            Issue.record("Expected a mutex bridge call")
            return
        }
        #expect(actual.count == arguments.count)
        #expect(Array(actual.dropLast()) == Array(arguments.dropLast()))
        #expect(canThrow == owner)
        #expect(thrownResult == (owner ? thrown : nil))
        if suspend {
            #expect(actual.last != placeholder)
            let continuation = try #require(actual.last)
            #expect(lowered.body.contains {
                guard case let .constValue(result, .symbolRef(symbol)) = $0 else { return false }
                return result == continuation && symbol == lowered.params.last?.symbol
            })
            #expect(lowered.body.contains { if case .returnIfEqual = $0 { return true }; return false })
            #expect(!lowered.body.contains {
                guard case let .call(_, name, _, _, _, _, _, _) = $0 else { return false }
                return interner.resolve(name) == "kk_coroutine_check_cancellation"
            })
        } else {
            #expect(actual == arguments)
        }
    }
}
