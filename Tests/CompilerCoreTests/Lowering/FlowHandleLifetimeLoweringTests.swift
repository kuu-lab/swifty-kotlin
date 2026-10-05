@testable import CompilerCore
import Testing

@Suite
struct FlowHandleLifetimeLoweringTests {
    @Test(arguments: [false, true])
    func doesNotReleaseLoopCarriedFlow(conditionalBackEdge: Bool) throws {
        let releases = try lowerFlowLifetime(conditionalBackEdge: conditionalBackEdge)
        #expect(releases.isEmpty)
    }

    @Test
    func releasesFlowAtFinalConsumeAfterLoop() throws {
        let releases = try lowerFlowLifetime(finalConsume: true)
        #expect(releases.count == 1)
        #expect(releases.first?.afterLoop == true)
    }

    @Test
    func releasesFlowRecreatedOnEachIteration() throws {
        let releases = try lowerFlowLifetime(createInLoop: true)
        #expect(releases.count == 1)
        #expect(releases.first?.afterLoop == false)
    }

    private func lowerFlowLifetime(
        conditionalBackEdge: Bool = false,
        finalConsume: Bool = false,
        createInLoop: Bool = false
    ) throws -> [(afterLoop: Bool, handle: KIRExprID)] {
        let interner = StringInterner()
        let arena = KIRArena()
        let handle = arena.appendTemporary()
        let callback = arena.appendExpr(.intLiteral(0))
        let condition = arena.appendExpr(.boolLiteral(false))
        let thrown = arena.appendTemporary()
        let create = KIRInstruction.call(
            symbol: nil, callee: interner.intern("flow"), arguments: [callback],
            result: handle, canThrow: false, thrownResult: nil
        )
        let collect = KIRInstruction.call(
            symbol: nil, callee: interner.intern("collect"), arguments: [handle, callback],
            result: nil, canThrow: true, thrownResult: thrown
        )
        var body: [KIRInstruction] = []
        if !createInLoop { body.append(create) }
        body.append(.label(10))
        if createInLoop { body.append(create) }
        body += [
            collect,
            .jumpIfNotNull(value: thrown, target: 20),
            .jump(30),
            .label(20),
            .call(symbol: nil, callee: interner.intern("println"), arguments: [thrown],
                  result: nil, canThrow: false, thrownResult: nil),
            .label(30),
        ]
        if conditionalBackEdge {
            body.append(.jumpIfEqual(lhs: condition, rhs: condition, target: 10))
        } else {
            body.append(.jumpIfEqual(lhs: condition, rhs: condition, target: 40))
            body.append(.jump(10))
        }
        body.append(.label(40))
        if finalConsume { body.append(collect) }
        body.append(.returnUnit)
        let functionID = arena.appendDecl(.function(KIRFunction(
            symbol: SymbolID(rawValue: 1), name: interner.intern("test"), params: [],
            returnType: TypeSystem().unitType, body: body, isSuspend: true, isInline: false
        )))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [functionID])], arena: arena)
        CoroutineLoweringPass().lowerFlowExpressions(module: module, ctx: makeKIRContext(interner: interner))
        let function = try #require(arena.decl(functionID)?.function)
        var afterLoop = false
        return function.body.compactMap { instruction in
            if case .label(40) = instruction { afterLoop = true }
            guard case let .call(_, callee, arguments, _, _, _, _, _) = instruction,
                  interner.resolve(callee) == "__kk_flow_release"
            else { return nil }
            return (afterLoop, arguments[0])
        }
    }
}
