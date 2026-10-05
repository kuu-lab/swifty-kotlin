@testable import CompilerCore
import Testing

@Suite
struct FlowScopeOwnershipTests {
    @Test(arguments: [0, 1, 3])
    func cleansUpLoopCarriedOwnership(iterations: Int) throws {
        let execution = try execute(iterations: iterations)
        #expect(execution.collections == iterations)
        #expect(execution.owners.isEmpty)
        #expect(execution.releases == 1)
    }

    @Test(arguments: [false, true])
    func cleansUpAliasesAndBorrowedConsumes(symbolBacked: Bool) throws {
        let execution = try execute(iterations: 3, alias: true, symbolBacked: symbolBacked)
        #expect(execution.collections == 3)
        #expect(execution.owners.isEmpty)
        #expect(execution.releases == (symbolBacked ? 4 : 1))
    }

    @Test(arguments: [false, true])
    func cleansUpOnlyInitializedBranchLocalHandles(define: Bool) throws {
        let execution = try execute(iterations: 0, branchDefinition: define)
        #expect(execution.owners.isEmpty)
        #expect(execution.releases == (define ? 1 : 0))
    }

    @Test(arguments: [false, true])
    func preservesFinalConsumeAfterLoop(finalConsume: Bool) throws {
        let execution = try execute(iterations: 3, finalConsume: finalConsume)
        #expect(execution.collections == (finalConsume ? 4 : 3))
        #expect(execution.owners.isEmpty)
        #expect(execution.releases == 1)
    }

    @Test(arguments: [0, 3])
    func cleansUpPerIterationHandlesWithoutDoubleRelease(iterations: Int) throws {
        let execution = try execute(iterations: iterations, createInLoop: true)
        #expect(execution.collections == iterations)
        #expect(execution.owners.isEmpty)
        #expect(execution.releases == iterations)
    }

    @Test(arguments: [false, true])
    func cleansUpOnEarlyAndExceptionalExits(exceptional: Bool) throws {
        let execution = try execute(iterations: 3, earlyExit: exceptional ? .exceptional : .normal)
        #expect(execution.collections == 1)
        #expect(execution.owners.isEmpty)
        #expect(execution.releases == 1)
    }

    @Test
    func cleansUpImplicitExceptionalReturns() throws {
        let execution = try execute(iterations: 3, implicitFailure: true)
        #expect(execution.collections == 1)
        #expect(execution.owners.isEmpty)
        #expect(execution.releases == 1)
    }

    @Test
    func balancesBorrowedConsumesOnImplicitCollectorFailure() throws {
        let execution = try execute(iterations: 3, alias: true, symbolBacked: true, collectorFailure: true)
        #expect(execution.collections == 1)
        #expect(execution.owners.isEmpty)
        #expect(execution.releases == 2)
    }

    @Test(arguments: [Escape.returned, .nonLocalReturned, .global, .captured, .unknownCall])
    func preservesEscapedHandles(escape: Escape) throws {
        let execution = try execute(iterations: 2, escape: escape)
        #expect(execution.collections == 2)
        #expect(execution.owners.count == 1)
        #expect(execution.releases == 0)
    }

    @Test(arguments: [false, true])
    func infersOwnedReturnsOnlyWithoutOtherEscapes(escapes: Bool) {
        let interner = StringInterner()
        let arena = KIRArena()
        let root = arena.appendTemporary()
        let alias = arena.appendTemporary()
        let callback = arena.appendExpr(.intLiteral(0))
        let symbol = SymbolID(rawValue: 1)
        var body: [KIRInstruction] = [
            .call(symbol: nil, callee: interner.intern("kk_flow_create"), arguments: [callback],
                  result: root, canThrow: false, thrownResult: nil),
            .copy(from: root, to: alias),
        ]
        if escapes { body.append(.storeGlobal(value: alias, symbol: SymbolID(rawValue: 2))) }
        body.append(.returnValue(alias))
        let declaration = arena.appendDecl(.function(KIRFunction(
            symbol: symbol, name: interner.intern("factory"), params: [],
            returnType: .invalid, body: body, isSuspend: false, isInline: false
        )))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [declaration])], arena: arena)
        let inferred = CoroutineLoweringPass().freshFlowFunctions(module: module, ctx: makeKIRContext(interner: interner))
        #expect(inferred.contains(symbol) == !escapes)
    }

    @Test(arguments: [false, true])
    func emissionResultsAreNotOwnedAndEmittedHandlesEscape(emitOwnedFlow: Bool) {
        let interner = StringInterner()
        let arena = KIRArena()
        let root = arena.appendTemporary()
        let emitted = arena.appendTemporary()
        let zero = arena.appendExpr(.intLiteral(0))
        let value = arena.appendExpr(.intLiteral(7))
        var body = KIRLoweringEmitContext()
        if emitOwnedFlow {
            body.append(.call(symbol: nil, callee: interner.intern("kk_flow_create"), arguments: [zero, zero],
                              result: root, canThrow: false, thrownResult: nil))
        }
        body.append(.call(symbol: nil, callee: interner.intern("kk_flow_emit"), arguments: [zero, emitOwnedFlow ? root : value, zero],
                          result: emitted, canThrow: false, thrownResult: nil))
        body.append(.returnUnit)
        let module = KIRModule(files: [], arena: arena)
        let cleaned = CoroutineLoweringPass().cleanUpOwnedFlows(
            body, module: module, ctx: makeKIRContext(interner: interner), freshFunctions: []
        )
        #expect(cleaned.instructions.count == body.instructions.count)
    }

    enum Escape: CaseIterable { case returned, nonLocalReturned, global, captured, unknownCall }
    private enum Exit { case normal, exceptional }
    private struct Execution {
        var collections = 0
        var releases = 0
        var owners: [Int: Int] = [:]
    }

    private func execute(
        iterations: Int,
        alias: Bool = false,
        symbolBacked: Bool = false,
        branchDefinition: Bool? = nil,
        createInLoop: Bool = false,
        finalConsume: Bool = false,
        earlyExit: Exit? = nil,
        implicitFailure: Bool = false,
        collectorFailure: Bool = false,
        escape: Escape? = nil
    ) throws -> Execution {
        let interner = StringInterner()
        let arena = KIRArena()
        let handle = arena.appendTemporary()
        let callback = arena.appendExpr(.intLiteral(0))
        let zero = arena.appendExpr(.intLiteral(0))
        let one = arena.appendExpr(.intLiteral(1))
        let limit = arena.appendExpr(.intLiteral(Int64(iterations)))
        let counter = arena.appendTemporary()
        let thrown = arena.appendTemporary()
        let use = alias ? arena.appendTemporary() : handle
        var body: [KIRInstruction] = [.copy(from: zero, to: counter)]
        if symbolBacked {
            body.append(.constValue(result: use, value: .symbolRef(SymbolID(rawValue: 99))))
        }
        let create = KIRInstruction.call(symbol: nil, callee: interner.intern("flow"), arguments: [callback], result: handle, canThrow: false, thrownResult: nil)
        let collect = KIRInstruction.call(symbol: nil, callee: interner.intern("collect"), arguments: [use, callback], result: nil, canThrow: true, thrownResult: collectorFailure ? nil : thrown)
        func appendCreate() {
            body.append(create)
            if alias { body.append(.copy(from: handle, to: use)) }
        }
        if let define = branchDefinition {
            let flag = arena.appendExpr(.intLiteral(define ? 1 : 0))
            body.append(.jumpIfEqual(lhs: flag, rhs: zero, target: 40))
        }
        if !createInLoop { appendCreate() }
        body += [.label(10), .jumpIfEqual(lhs: counter, rhs: limit, target: 40)]
        if createInLoop { appendCreate() }
        body.append(collect)
        if implicitFailure {
            body.append(.call(symbol: nil, callee: interner.intern("fail"), arguments: [], result: nil, canThrow: true, thrownResult: nil))
        }
        if let earlyExit {
            body.append(earlyExit == .normal ? .returnUnit : .rethrow(value: thrown))
        }
        body += [.binary(op: .add, lhs: counter, rhs: one, result: counter), .jump(10), .label(40)]
        if finalConsume { body.append(collect) }
        switch escape {
        case .returned: body.append(.returnValue(use))
        case .nonLocalReturned: body.append(.nonLocalReturn(use, target: .function(SymbolID(rawValue: 1))))
        case .global: body.append(.storeGlobal(value: use, symbol: SymbolID(rawValue: 100)))
        case .captured:
            body.append(.call(symbol: nil, callee: interner.intern("kk_coroutine_launcher_arg_set"), arguments: [callback, zero, use], result: nil, canThrow: false, thrownResult: nil))
        case .unknownCall:
            body.append(.call(symbol: nil, callee: interner.intern("save"), arguments: [use], result: nil, canThrow: false, thrownResult: nil))
        case nil: break
        }
        body.append(.returnUnit)
        let functionID = arena.appendDecl(.function(KIRFunction(
            symbol: SymbolID(rawValue: 1), name: interner.intern("test"), params: [],
            returnType: TypeSystem().unitType, body: body, isSuspend: true, isInline: false
        )))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [functionID])], arena: arena)
        CoroutineLoweringPass().lowerFlowExpressions(module: module, ctx: makeKIRContext(interner: interner))
        let declaration = try #require(arena.decl(functionID))
        guard case let .function(function) = declaration else {
            Issue.record("Expected function declaration")
            return Execution()
        }
        #expect(function.body.count == function.instructionLocations.count)
        if escape == .nonLocalReturned {
            #expect(function.body.contains(.nonLocalReturn(use, target: .function(SymbolID(rawValue: 1)))))
        }
        let labels = Dictionary(uniqueKeysWithValues: function.body.enumerated().compactMap { index, instruction -> (Int32, Int)? in
            if case let .label(label) = instruction { return (label, index) }
            return nil
        })
        var values: [KIRExprID: Int] = [:]
        func value(_ expr: KIRExprID) throws -> Int {
            if let value = values[expr] { return value }
            if case let .intLiteral(number)? = arena.expr(expr) { return Int(number) }
            Issue.record("Read uninitialized expression \(expr.rawValue)")
            return try #require(values[expr])
        }
        var execution = Execution()
        var nextHandle = 1000
        var pc = 0
        var steps = 0
        while function.body.indices.contains(pc) {
            steps += 1
            #expect(steps < 1000)
            if steps >= 1000 { break }
            switch function.body[pc] {
            case let .constValue(result, kind):
                switch kind {
                case .null: values[result] = 0
                case let .intLiteral(number): values[result] = Int(number)
                case .symbolRef: values[result] = -1
                default: Issue.record("Unsupported constant")
                }
            case let .copy(from, to): values[to] = try value(from)
            case let .binary(.add, lhs, rhs, result): values[result] = try value(lhs) + value(rhs)
            case let .jump(target): pc = try #require(labels[target]); continue
            case let .jumpIfEqual(lhs, rhs, target):
                if try value(lhs) == value(rhs) { pc = try #require(labels[target]); continue }
            case let .jumpIfNotNull(expr, target):
                if try value(expr) != 0 { pc = try #require(labels[target]); continue }
            case let .call(_, callee, args, result, _, thrown, _, _):
                switch interner.resolve(callee) {
                case "kk_flow_create":
                    nextHandle += 1
                    values[try #require(result)] = nextHandle
                    execution.owners[nextHandle] = 1
                case "__kk_flow_retain":
                    let handle = try value(args[0])
                    #expect(execution.owners[handle] != nil)
                    execution.owners[handle, default: 0] += 1
                    values[try #require(result)] = handle
                case "__kk_flow_release":
                    let handle = try value(args[0])
                    let count = try #require(execution.owners[handle], "Release must target initialized, live ownership")
                    execution.releases += 1
                    if count == 1 { execution.owners.removeValue(forKey: handle) }
                    else { execution.owners[handle] = count - 1 }
                case "kk_flow_collect":
                    #expect(execution.owners[try value(args[0])] != nil, "Collection must not use a released handle")
                    execution.collections += 1
                default: break
                }
                if let thrown {
                    let name = interner.resolve(callee)
                    values[thrown] = name == "fail" || (collectorFailure && name == "kk_flow_collect") ? 1 : 0
                }
            case .returnUnit, .returnValue, .rethrow, .nonLocalReturn: return execution
            default: break
            }
            pc += 1
        }
        return execution
    }
}
