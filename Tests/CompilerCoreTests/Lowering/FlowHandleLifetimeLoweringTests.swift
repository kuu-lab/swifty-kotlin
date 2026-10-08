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
        let function = try #require(arena.decl(functionID)?.function)
        let names = FlowLoweringNames(
            flow: interner.intern("flow"), emit: interner.intern("emit"),
            collect: interner.intern("collect"), collectLatest: interner.intern("collectLatest"),
            map: interner.intern("map"), filter: interner.intern("filter"),
            take: interner.intern("take"), transform: interner.intern("transform"),
            single: interner.intern("single"), takeWhile: interner.intern("takeWhile"),
            dropWhile: interner.intern("dropWhile"), flatMapConcat: interner.intern("flatMapConcat"),
            flatMapMerge: interner.intern("flatMapMerge"), flatMapLatest: interner.intern("flatMapLatest"),
            combine: interner.intern("combine"), zip: interner.intern("zip"),
            merge: interner.intern("merge"), buffer: interner.intern("buffer"),
            conflate: interner.intern("conflate"), flowOn: interner.intern("flowOn"),
            debounce: interner.intern("debounce"), sample: interner.intern("sample"),
            catchHandler: interner.intern("catch"),
            retry: interner.intern("retry"), retryWhen: interner.intern("retryWhen"),
            toList: interner.intern("toList"), first: interner.intern("first"),
            kkFlowCreate: LoweringTestRuntime.callee("flow_create", interner: interner), kkFlowEmit: LoweringTestRuntime.callee("flow_emit", interner: interner),
            kkFlowCollect: LoweringTestRuntime.callee("flow_collect", interner: interner), kkFlowCollectLatest: LoweringTestRuntime.callee("flow_collectLatest", interner: interner),
            kkFlowRetain: LoweringTestRuntime.callee("flow_retain", interner: interner), kkFlowRelease: LoweringTestRuntime.callee("flow_release", interner: interner),
            kkFlowToList: LoweringTestRuntime.callee("flow_to_list", interner: interner), kkFlowFirst: LoweringTestRuntime.callee("flow_first", interner: interner),
            kkFlowSingle: LoweringTestRuntime.callee("flow_single", interner: interner), kkFlowZip: LoweringTestRuntime.callee("flow_zip", interner: interner),
            kkFlowCombine: LoweringTestRuntime.callee("flow_combine", interner: interner), kkFlowMerge: LoweringTestRuntime.callee("flow_merge", interner: interner),
            kkFlowFlatMapConcat: LoweringTestRuntime.callee("flow_flat_map_concat", interner: interner),
            kkFlowFlatMapMerge: LoweringTestRuntime.callee("flow_flat_map_merge", interner: interner),
            kkFlowFlatMapLatest: LoweringTestRuntime.callee("flow_flat_map_latest", interner: interner)
        )
        var flowExprIDs: Set<Int32> = [handle.rawValue]
        var remainingConsumes = [handle.rawValue: finalConsume ? 2 : 1]
        // Pin lexical consume releases separately from guarded scope-exit ownership cleanup.
        let rewritten = CoroutineLoweringPass().rewriteFlowInstructions(
            originalBody: function.body, originalLocations: function.instructionLocations,
            module: module, ctx: makeKIRContext(interner: interner),
            flowExprIDs: &flowExprIDs, remainingConsumes: &remainingConsumes,
            symbolByExprRaw: [:], names: names, isFlowScopeFunction: false
        )
        #expect(rewritten.instructions.filter { instruction in
            if case .call(_, names.kkFlowCollect, _, _, _, _, _, _) = instruction { return true }
            return false
        }.count == (finalConsume ? 2 : 1))
        var afterLoop = false
        return rewritten.instructions.compactMap { instruction in
            if case .label(40) = instruction { afterLoop = true }
            guard case let .call(_, callee, arguments, _, _, _, _, _) = instruction,
                  callee == names.kkFlowRelease
            else { return nil }
            return (afterLoop, arguments[0])
        }
    }
}
