#if canImport(Testing)
@testable import CompilerCore
import Foundation
import RuntimeABI
import Testing

extension LoweringPassRegressionTests {
    @Test
    func testCoroutineLoweringRewritesSequenceBuilderProducersToCPSRuntimeABI() throws {
        let source = """
        fun main() {
            val seq = sequence {
                yield(1)
                yield(2)
            }
            val iter = iterator {
                yield(3)
            }
            println(seq)
            println(iter)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "CoroutineBuilderCPS", emit: .kirDump)
            try runToLowering(ctx)

            let module = try #require(ctx.kir)
            let functions = findAllKIRFunctions(in: module)
            let allCallees = functions.flatMap { function in
                extractCallees(from: function.body, interner: ctx.interner)
            }

            #expect(allCallees.contains(RuntimeCall.sequenceBuilderBuildCoro.name), "Callees: \(allCallees)")
            #expect(allCallees.contains(RuntimeCall.iteratorBuilderBuildCoro.name), "Callees: \(allCallees)")

            let builderBuildCalls = functions.flatMap { function -> [(String, Int)] in
                function.body.compactMap { instruction in
                    guard case let .call(_, callee, arguments, _, _, _, _, _) = instruction else {
                        return nil
                    }
                    let name = ctx.interner.resolve(callee)
                    guard name == RuntimeCall.sequenceBuilderBuildCoro.name || name == RuntimeCall.iteratorBuilderBuildCoro.name else {
                        return nil
                    }
                    return (name, arguments.count)
                }
            }
            #expect(builderBuildCalls.allSatisfy { _, argumentCount in argumentCount == 3 }, "Builder calls: \(builderBuildCalls)")

            let yieldFunctions = functions.filter { function in
                extractCallees(from: function.body, interner: ctx.interner).contains(RuntimeCall.sequenceBuilderYield.name)
            }
            #expect(!yieldFunctions.isEmpty, "Expected lowered builder functions to call __kk_sequence_builder_yield")
            #expect(yieldFunctions.allSatisfy { function in
                function.body.contains { instruction in
                    if case .returnIfEqual = instruction {
                        return true
                    }
                    return false
                }
            }, "yield() calls in CPS builders must propagate COROUTINE_SUSPENDED")
        }
    }

    @Test
    func testCoroutineLoweringKeepsYieldAllSequenceBuildersOnLegacyRuntimeABI() throws {
        let source = """
        fun main() {
            val seq = sequence {
                yieldAll(listOf(1, 2))
            }
            println(seq)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "SequenceBuilderYieldAllLegacy", emit: .kirDump)
            try runToLowering(ctx)

            let module = try #require(ctx.kir)
            let functions = findAllKIRFunctions(in: module)
            let allCallees = functions.flatMap { function in
                extractCallees(from: function.body, interner: ctx.interner)
            }

            #expect(allCallees.contains(RuntimeCall.sequenceBuilderBuild.name), "Callees: \(allCallees)")
            #expect(!allCallees.contains(RuntimeCall.sequenceBuilderBuildCoro.name), "Callees: \(allCallees)")
        }
    }

    @Test
    func testMixedBuilderYieldAllPreservesInitialProbeThrowChannel() throws {
        let source = """
        fun main() {
            val seq = sequence<Int> {
                yield(1)
                try {
                    yieldAll(iterator<Int> { if (false) yield(99); throw IllegalArgumentException("nested") })
                } catch (e: IllegalArgumentException) { yield(2) }
            }
            println(seq.toList())
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToLowering(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            let functions = findAllKIRFunctions(in: try #require(ctx.kir))
            let calls = functions.flatMap { function in
                function.body.compactMap { instruction -> (Bool, KIRExprID?)? in
                    guard case let .call(_, callee, _, _, canThrow, thrown, _, _) = instruction,
                          callee == ctx.interner.intern(RuntimeCall.sequenceBuilderYieldAllChecked.name)
                    else { return nil }
                    return (canThrow, thrown)
                }
            }
            #expect(!calls.isEmpty)
            #expect(calls.allSatisfy { $0.0 && $0.1 != nil })
        }
    }

    @Test
    func testCoroutineLoweringRewritesRangeLoopSequenceBuildersToCPSRuntimeABI() throws {
        let source = """
        fun main() {
            val seq = sequence {
                for (i in 1..5) {
                    yield(i * i)
                }
            }
            println(seq)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "SequenceBuilderRangeLoopCPS", emit: .kirDump)
            try runToLowering(ctx)

            let module = try #require(ctx.kir)
            let functions = findAllKIRFunctions(in: module)
            let allCallees = functions.flatMap { function in
                extractCallees(from: function.body, interner: ctx.interner)
            }

            #expect(allCallees.contains(RuntimeCall.sequenceBuilderBuildCoro.name), "Callees: \(allCallees)")

            let rangeYieldFunctions = functions.filter { function in
                let callees = extractCallees(from: function.body, interner: ctx.interner)
                // ARCH-012: the induction loop must retain CPS suspension
                // handling without falling back to the range iterator ABI.
                return callees.contains(RuntimeCall.sequenceBuilderYield.name)
                    && callees.contains(CompilerCall.intRangeInductionLe.name)
                    && callees.contains(CompilerCall.intRangeInductionAdd.name)
                    && !callees.contains(RuntimeCall.rangeForInIterator.name)
                    && !callees.contains(RuntimeCall.rangeForInHasNext.name)
                    && !callees.contains(RuntimeCall.rangeForInNext.name)
            }
            #expect(!rangeYieldFunctions.isEmpty, "Expected a CPS-lowered range-loop builder, callees: \(allCallees)")
            #expect(rangeYieldFunctions.allSatisfy { function in
                function.body.contains { instruction in
                    if case .returnIfEqual = instruction {
                        return true
                    }
                    return false
                }
            }, "range-loop yield() calls must propagate COROUTINE_SUSPENDED")
        }
    }

    @Test
    func testCoroutineLoweringSpillsAndReloadsLiveValuesAcrossSuspension() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()

        let suspendSym = SymbolID(rawValue: 1900)
        let liveValue = arena.appendExpr(.temporary(0))
        let callResult = arena.appendExpr(.temporary(1))
        let summedResult = arena.appendExpr(.temporary(2))

        let suspendFn = KIRFunction(
            symbol: suspendSym,
            name: interner.intern("suspendTarget"),
            params: [],
            returnType: types.make(.primitive(.int, .nonNull)),
            body: [
                .constValue(result: liveValue, value: .intLiteral(41)),
                .call(symbol: suspendSym, callee: interner.intern("suspendTarget"), arguments: [], result: callResult, canThrow: false, thrownResult: nil),
                .binary(op: .add, lhs: liveValue, rhs: callResult, result: summedResult),
                .returnValue(summedResult),
            ],
            isSuspend: true,
            isInline: false
        )

        let suspendID = arena.appendDecl(.function(suspendFn))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [suspendID])], arena: arena)
        try runLowering(module: module, interner: interner, moduleName: "CoroutineSpill")

        let loweredSuspend = try loweredSuspendFunction(originalNamed: "suspendTarget", in: module, interner: interner)

        let loweredCalls = extractCallees(from: loweredSuspend.body, interner: interner)
        #expect(loweredCalls.contains(RuntimeCall.coroutineStateSetSpill.name))
        #expect(loweredCalls.contains(RuntimeCall.coroutineStateGetSpill.name))
        #expect(loweredCalls.contains(RuntimeCall.coroutineStateSetCompletion.name))
        #expect(loweredCalls.contains(RuntimeCall.coroutineStateGetCompletion.name))

        let setSpillCount = loweredCalls.filter { $0 == RuntimeCall.coroutineStateSetSpill.name }.count
        let getSpillCount = loweredCalls.filter { $0 == RuntimeCall.coroutineStateGetSpill.name }.count
        #expect(setSpillCount == 1)
        #expect(getSpillCount == 1)

        let throwFlags = extractThrowFlags(from: loweredSuspend.body, interner: interner)
        #expect(loweredCalls.contains(RuntimeCall.coroutineCallDirectSuspend.name))
        #expect(throwFlags[RuntimeCall.coroutineCallDirectSuspend.name]?.allSatisfy { $0 == false } == true)
        #expect(throwFlags[RuntimeCall.coroutineStateSetSpill.name]?.allSatisfy { $0 == false } == true)
        #expect(throwFlags[RuntimeCall.coroutineStateGetSpill.name]?.allSatisfy { $0 == false } == true)
        #expect(throwFlags[RuntimeCall.coroutineStateSetCompletion.name]?.allSatisfy { $0 == false } == true)
        #expect(throwFlags[RuntimeCall.coroutineStateGetCompletion.name]?.allSatisfy { $0 == false } == true)
    }

    @Test
    func testCoroutineLivenessTracksGlobalLoadDefinitionsAndStoreUses() {
        let pass = CoroutineLoweringPass()
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()
        let globalSymbol = SymbolID(rawValue: 1901)
        let loadResult = arena.appendTemporary(type: types.stringType)
        let loadedLiveOut = pass.computeLiveOutByInstruction(
            [
                .call(
                    symbol: nil,
                    callee: interner.intern("suspendPoint"),
                    arguments: [],
                    result: nil,
                    canThrow: false,
                    thrownResult: nil
                ),
                .loadGlobal(result: loadResult, symbol: globalSymbol),
                .returnValue(loadResult),
            ],
            arena: arena
        )
        #expect(!(loadedLiveOut[0] ?? []).contains(loadResult))

        let storedValue = arena.appendTemporary(type: types.stringType)
        let storedLiveOut = pass.computeLiveOutByInstruction(
            [
                .constValue(result: storedValue, value: .stringLiteral(interner.intern("before"))),
                .call(
                    symbol: nil,
                    callee: interner.intern("suspendPoint"),
                    arguments: [],
                    result: nil,
                    canThrow: false,
                    thrownResult: nil
                ),
                .storeGlobal(value: storedValue, symbol: globalSymbol),
                .returnUnit,
            ],
            arena: arena
        )
        #expect((storedLiveOut[1] ?? []).contains(storedValue))
    }

    @Test
    func testCoroutineLoweringRewritesSuspendCoroutineIntrinsicToFunctionInvoke() throws {
        let source = """
        import kotlin.coroutines.intrinsics.COROUTINE_SUSPENDED
        import kotlin.coroutines.intrinsics.suspendCoroutineUninterceptedOrReturn

        suspend fun probe(): Int {
            return suspendCoroutineUninterceptedOrReturn { continuation ->
                7
            }
        }

        fun main(): Any? = runBlocking(probe)
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "CoroutineIntrinsicRewrite", emit: .kirDump)
            try runToLowering(ctx)

            let module = try #require(ctx.kir)
            let loweredProbe = try loweredSuspendFunction(originalNamed: "probe", in: module, interner: ctx.interner)

            let loweredCalls = extractCallees(from: loweredProbe.body, interner: ctx.interner)
            #expect(!loweredCalls.contains("suspendCoroutineUninterceptedOrReturn"))
            #expect(loweredCalls.contains(RuntimeCall.coroutineSuspended.name), "Callees: \(loweredCalls)")
            #expect(loweredCalls.contains(RuntimeCall.coroutineStateEnter.name), "Callees: \(loweredCalls)")
            #expect(loweredCalls.contains(RuntimeCall.coroutineStateExit.name), "Callees: \(loweredCalls)")

            let throwFlags = extractThrowFlags(from: loweredProbe.body, interner: ctx.interner)
            #expect(throwFlags[RuntimeCall.coroutineSuspended.name]?.allSatisfy { $0 == false } == true)
        }
    }

    @Test
    func testCoroutineLoweringSynthesizesContinuationNominalTypeLayoutAndSignature() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()
        let symbols = SymbolTable()
        let bindings = BindingTable()
        let diagnostics = DiagnosticEngine()

        let packageName = interner.intern("pkg")
        let suspendName = interner.intern("suspendTarget")
        let parameterName = interner.intern("value")
        let range = makeRange()
        let intType = types.make(.primitive(.int, .nonNull))

        let suspendSymbol = symbols.define(
            kind: .function,
            name: suspendName,
            fqName: [packageName, suspendName],
            declSite: range,
            visibility: .public,
            flags: [.suspendFunction]
        )
        let parameterSymbol = symbols.define(
            kind: .valueParameter,
            name: parameterName,
            fqName: [packageName, suspendName, parameterName],
            declSite: range,
            visibility: .private
        )
        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [intType],
                returnType: intType,
                isSuspend: true,
                valueParameterSymbols: [parameterSymbol]
            ),
            for: suspendSymbol
        )

        let liveValue = arena.appendExpr(.temporary(0), type: intType)
        let callResult = arena.appendExpr(.temporary(1), type: intType)
        let sumResult = arena.appendExpr(.temporary(2), type: intType)

        let suspendFunction = KIRFunction(
            symbol: suspendSymbol,
            name: suspendName,
            params: [KIRParameter(symbol: parameterSymbol, type: intType)],
            returnType: intType,
            body: [
                .constValue(result: liveValue, value: .symbolRef(parameterSymbol)),
                .call(
                    symbol: suspendSymbol,
                    callee: suspendName,
                    arguments: [liveValue],
                    result: callResult,
                    canThrow: false,
                    thrownResult: nil
                ),
                .binary(op: .add, lhs: liveValue, rhs: callResult, result: sumResult),
                .returnValue(sumResult),
            ],
            isSuspend: true,
            isInline: false
        )

        let suspendID = arena.appendDecl(.function(suspendFunction))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [suspendID])], arena: arena)

        let ctx = try runLowering(module: module, interner: interner, moduleName: "CoroutineContinuationType", sema: makeSemaModule(symbols: symbols, types: types, bindings: bindings, diagnostics: diagnostics).ctx, diagnostics: diagnostics)

        let sema = try #require(ctx.sema)
        let loweredSuspend = try loweredSuspendFunction(originalNamed: interner.resolve(suspendName), in: module, interner: interner)
        // Sema and KIR allocate separate symbols for the same lowered declaration.
        let loweredSemaSymbol = try #require(sema.symbols.allSymbols().first {
            $0.kind == .function && $0.name == loweredSuspend.name
        })
        let loweredSignature = try #require(sema.symbols.functionSignature(for: loweredSemaSymbol.id))
        let continuationParameterType = try #require(loweredSignature.parameterTypes.last)
        guard case let .classType(classType) = types.kind(of: continuationParameterType) else {
            Issue.record("Expected lowered continuation parameter type to be class type.")
            return
        }
        let continuationTypeSymbol = try #require(sema.symbols.symbol(classType.classSymbol))
        #expect(continuationTypeSymbol.kind == .class)
        #expect(continuationTypeSymbol.flags.contains(.synthetic))

        let continuationFields = sema.symbols.allSymbols().filter { symbol in
            symbol.kind == .field &&
                symbol.fqName.count == continuationTypeSymbol.fqName.count + 1 &&
                zip(continuationTypeSymbol.fqName, symbol.fqName).allSatisfy { $0 == $1 }
        }
        let layout = try #require(sema.symbols.nominalLayout(for: continuationTypeSymbol.id))
        #expect(layout.instanceFieldCount >= 3)
        let labelField = try #require(continuationFields.first(where: { $0.name == interner.intern("$label") }))
        let completionField = try #require(continuationFields.first(where: { $0.name == interner.intern("$completion") }))
        let spillField = try #require(continuationFields.first(where: { $0.name == interner.intern("$spill0") }))
        let labelOffset = try #require(layout.fieldOffsets[labelField.id])
        let completionOffset = try #require(layout.fieldOffsets[completionField.id])
        let spillOffset = try #require(layout.fieldOffsets[spillField.id])
        #expect(labelOffset < completionOffset)
        #expect(completionOffset < spillOffset)

        let nominalSymbols = module.arena.declarations.compactMap { decl -> SymbolID? in
            guard case let .nominalType(nominal) = decl else {
                return nil
            }
            return nominal.symbol
        }
        #expect(nominalSymbols.contains(continuationTypeSymbol.id))
    }

    @Test
    func testSuspendExceptionPropagationKeepsThrowingChannelAcrossSuspendChain() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()

        let mainSymbol = SymbolID(rawValue: 2100)
        let topSymbol = SymbolID(rawValue: 2101)
        let leafSymbol = SymbolID(rawValue: 2102)

        let mainResult = arena.appendExpr(.temporary(0))
        let topResult = arena.appendExpr(.temporary(1))
        let leafResult = arena.appendExpr(.temporary(2))

        let mainFunction = KIRFunction(
            symbol: mainSymbol,
            name: interner.intern("main"),
            params: [],
            returnType: types.unitType,
            body: [
                .call(symbol: topSymbol, callee: interner.intern("top"), arguments: [], result: mainResult, canThrow: false, thrownResult: nil),
                .returnValue(mainResult),
            ],
            isSuspend: false,
            isInline: false
        )
        let topFunction = KIRFunction(
            symbol: topSymbol,
            name: interner.intern("top"),
            params: [],
            returnType: types.unitType,
            body: [
                .call(symbol: leafSymbol, callee: interner.intern("leaf"), arguments: [], result: topResult, canThrow: false, thrownResult: nil),
                .returnValue(topResult),
            ],
            isSuspend: true,
            isInline: false
        )
        let leafFunction = KIRFunction(
            symbol: leafSymbol,
            name: interner.intern("leaf"),
            params: [],
            returnType: types.unitType,
            body: [
                .call(symbol: nil, callee: interner.intern("external_throwing"), arguments: [], result: leafResult, canThrow: false, thrownResult: nil),
                .returnValue(leafResult),
            ],
            isSuspend: true,
            isInline: false
        )

        let mainID = arena.appendDecl(.function(mainFunction))
        _ = arena.appendDecl(.function(topFunction))
        _ = arena.appendDecl(.function(leafFunction))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [mainID])], arena: arena)

        try runLowering(module: module, interner: interner, moduleName: "CoroutineThrowFlags")

        let loweredMain = try findKIRFunction(named: "main", in: module, interner: interner)
        let loweredTop = try loweredSuspendFunction(originalNamed: "top", in: module, interner: interner)
        let loweredLeaf = try loweredSuspendFunction(originalNamed: "leaf", in: module, interner: interner)

        let mainThrowFlags = extractThrowFlags(from: loweredMain.body, interner: interner)
        #expect(mainThrowFlags[interner.resolve(loweredTop.name)]?.allSatisfy { $0 == true } == true)

        let topThrowFlags = extractThrowFlags(from: loweredTop.body, interner: interner)
        #expect(topThrowFlags[RuntimeCall.coroutineCallDirectSuspend.name]?.allSatisfy { $0 == false } == true)
        #expect(topThrowFlags[RuntimeCall.coroutineStateSetLabel.name]?.allSatisfy { $0 == false } == true)
        #expect(topThrowFlags[RuntimeCall.coroutineStateSetCompletion.name]?.allSatisfy { $0 == false } == true)

        let leafThrowFlags = extractThrowFlags(from: loweredLeaf.body, interner: interner)
        #expect(leafThrowFlags["external_throwing"]?.allSatisfy { $0 == true } == true)
    }

    @Test
    func testSuspendCoroutineLoweringEmitsRuntimeSuspendHelper() throws {
        let source = """
        import kotlin.coroutines.*
        import kotlinx.coroutines.runBlocking

        suspend fun probe(): Int {
            return suspendCoroutine<Int> { cont: Continuation<Int> ->
                cont.resume(42)
            }
        }

        fun main(): Int = runBlocking { probe() }
        """

        try withTemporaryFile(contents: source) { path in
            // Include the bundled inline builder body; kirDump omits stdlib bodies.
            let ctx = makeCompilationContext(inputs: [path], moduleName: "SuspendCoroutineLowering", emit: .executable)
            try runToLowering(ctx)
            #expect(!ctx.diagnostics.hasError, "Diagnostics: \(ctx.diagnostics.diagnostics)")

            let module = try #require(ctx.kir)
            let loweredSuspend = try loweredSuspendFunction(originalNamed: "probe", in: module, interner: ctx.interner)

            let loweredCallees = extractCallees(from: loweredSuspend.body, interner: ctx.interner)
            // The source-backed builder inlines the intrinsic invocation protocol.
            #expect(!loweredCallees.contains(RuntimeCall.suspendCoroutine.name))
            #expect(!loweredCallees.contains("suspendCoroutineUninterceptedOrReturn"))
            #expect(!loweredCallees.contains("<suspendCoroutineUninterceptedOrReturn>"))
            #expect(loweredCallees.contains(RuntimeCall.coroutineStateEnter.name))
            #expect(loweredCallees.contains(RuntimeCall.coroutineStateExit.name))
            let invokeABI = try #require(RuntimeABISpec.byName[RuntimeCall.functionInvoke.name])
            let invokeResults = Set(loweredSuspend.body.compactMap { instruction -> KIRExprID? in
                guard case let .call(_, callee, _, result, canThrow, _, _, _) = instruction,
                      callee == ctx.interner.intern(RuntimeCall.functionInvoke.name)
                else { return nil }
                #expect(canThrow == invokeABI.isThrowing)
                return result
            })
            let suspendedResults = Set(loweredSuspend.body.compactMap { instruction -> KIRExprID? in
                guard case let .call(_, callee, _, result, _, _, _, _) = instruction,
                      callee == ctx.interner.intern(RuntimeCall.coroutineSuspended.name)
                else { return nil }
                return result
            })
            #expect(loweredSuspend.body.contains { instruction in
                guard case let .returnIfEqual(lhs, rhs) = instruction else { return false }
                return invokeResults.contains(lhs) && suspendedResults.contains(rhs)
            }, "Expected the intrinsic result to propagate COROUTINE_SUSPENDED")
        }
    }
}
#endif
