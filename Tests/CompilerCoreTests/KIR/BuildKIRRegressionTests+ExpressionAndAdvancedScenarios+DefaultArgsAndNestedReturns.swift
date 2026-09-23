#if canImport(Testing)
@testable import CompilerCore
import Testing

extension BuildKIRRegressionTests {

    /// Built once per process: `static let` initializes under `swift_once`, so
    /// parallel tests share a single compile. The previous check-then-set over
    /// a mutable static allowed concurrent tests to each miss the cache and
    /// re-pay the bundled-stdlib compile.
    private static nonisolated(unsafe) let _sharedDefaultArgsCtx = Result<CompilationContext, any Error> {
        let sources: [String] = [
            """
            package sample0
            fun main0() {
                val parts = "1,2,3".split(",")
                println(parts)
            }
            """,
            """
            package sample1
            fun add1(a: Int, b: Int = 10): Int = a + b
            fun main1() = add1(5, 20)
            """,
            """
            package sample2
            fun withDep2(a: Int, b: Int = a + 1): Int = a + b
            fun main2() = withDep2(10)
            """,
            """
            package sample3
            fun chain3(a: Int = 1, b: Int = a + 10, c: Int = b + 100): Int = a + b + c
            fun main3() = chain3()
            """,
            """
            package sample4
            fun Int.addDefault4(n: Int = this + 1): Int = this + n
            fun main4() = 5.addDefault4()
            """,
            """
            package sample5
            fun compute5(a: Int, b: Int = a + 1): Int = a + b
            fun main5() = compute5(5)
            """,
            """
            package sample6
            fun choose6(flag: Boolean): Int {
                if (flag) {
                    return 1
                }
                return 0
            }
            """,
            """
            package sample7
            fun pick7(flag: Boolean): Int {
                if (flag) {
                    return 1
                } else {
                    return 2
                }
            }
            """,
            """
            package sample8
            fun describe8(x: Int): Int {
                return when (x) {
                    1 -> return 10
                    2 -> return 20
                    else -> 0
                }
            }
            """,
            """
            package sample9
            fun choose9(flag: Boolean): Int {
                if (flag) {
                    return 1
                }
                return 0
            }
            """,
            """
            package sample10
            class Holder {
                val transform: (Int) -> Int = { it + 1 }
            }
            fun use10(h: Holder): Int = h.transform(5)
            """,
            """
            package sample11
            interface Foo11 {
                fun bar11(x: Int, y: Int = x + 1): Int
            }
            class FooImpl11 : Foo11 {
                override fun bar11(x: Int, y: Int): Int = x + y
            }
            fun main11(): Int {
                val f: Foo11 = FooImpl11()
                return f.bar11(10)
            }
            """,
            """
            package sample12
            open class Base12 {
                open fun baz12(x: Int, y: Int = 100): Int = x + y
            }
            class Derived12 : Base12() {
                override fun baz12(x: Int, y: Int): Int = x - y
            }
            fun main12(): Int {
                val d: Base12 = Derived12()
                return d.baz12(5)
            }
            """
        ]
        let ctx = makeContextFromSources(sources)
        try runToKIR(ctx)
        return ctx
    }

    private func sharedDefaultArgsCtx() throws -> CompilationContext {
        try Self._sharedDefaultArgsCtx.get()
    }

    @Test
    func testExternalStringStubWithDefaultArgsDoesNotCallDefaultStub() throws {
        let ctx = try sharedDefaultArgsCtx()

        let module = try #require(ctx.kir)
        let mainBody = try findKIRFunctionBody(named: "main0", in: module, interner: ctx.interner)
        let callees = extractCallees(from: mainBody, interner: ctx.interner)
        #expect(!callees.contains("kk_string_split_flat"), "String.split should no longer lower directly to kk_string_split_flat: \(callees)")
        #expect(
            callees.contains("split") || callees.contains("__kk_string_split"),
            "Expected source-backed String.split path, got: \(callees)"
        )
        #expect(!(callees.contains { $0.contains("split$default") }),
                       "External string stubs must not route through $default: \(callees)")
    }



    @Test
    func testDefaultArgNoStubWhenAllArgsProvided() throws {
        let ctx = try sharedDefaultArgsCtx()

        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "main1", in: module, interner: ctx.interner)
        let callees = extractCallees(from: body, interner: ctx.interner)
        #expect(callees.contains("add1"), "Expected direct call to add1, got: \(callees)")
        #expect(!(callees.contains("add1$default")), "Should not call stub when all args provided, got: \(callees)")
    }


    // MARK: - Default Argument Callee-Context Semantics (P5-56)


    @Test
    func testDefaultArgStubBindsPrecedingParameterForDefaultExpression() throws {
        let ctx = try sharedDefaultArgsCtx()

        let module = try #require(ctx.kir)
        // Call site must route through $default stub
        let mainBody = try findKIRFunctionBody(named: "main2", in: module, interner: ctx.interner)
        let mainCallees = extractCallees(from: mainBody, interner: ctx.interner)
        #expect(mainCallees.contains("withDep2$default"),
                      "Expected call to withDep2$default stub, got: \(mainCallees)")

        // Stub must exist and call the original function
        let stubFunction = findAllKIRFunctions(in: module).compactMap { function -> KIRFunction? in
            return ctx.interner.resolve(function.name) == "withDep2$default" ? function : nil
        }.first
        #expect(stubFunction != nil, "Expected withDep2$default stub function")
        if let stub = stubFunction {
            let stubCallees = extractCallees(from: stub.body, interner: ctx.interner)
            #expect(stubCallees.contains("withDep2"),
                          "Stub should call original withDep2, got: \(stubCallees)")
            // Stub body must contain a binary add for the default expression `a + 1`
            let hasBinaryAdd = stub.body.contains { instruction in
                guard case let .binary(op, _, _, _) = instruction else { return false }
                return op == .add
            }
            #expect(hasBinaryAdd,
                          "Stub should evaluate default `a + 1` with a binary add instruction")
        }
    }



    @Test
    func testDefaultArgStubEvaluatesMultipleDefaultsLeftToRightWithDependencies() throws {
        let ctx = try sharedDefaultArgsCtx()

        let module = try #require(ctx.kir)
        let stubFunction = findAllKIRFunctions(in: module).compactMap { function -> KIRFunction? in
            return ctx.interner.resolve(function.name) == "chain3$default" ? function : nil
        }.first
        #expect(stubFunction != nil, "Expected chain3$default stub function")
        if let stub = stubFunction {
            // The stub should have 3 original params + 1 mask param = 4 params
            #expect(stub.params.count == 4,
                           "Stub should have 3 original params + mask, got \(stub.params.count)")

            // Verify label pairs: each default param generates skip/after labels.
            // 3 defaults → 6 labels (2 per default), processed left-to-right.
            var labelOrder: [Int32] = []
            for instruction in stub.body {
                if case let .label(id) = instruction {
                    labelOrder.append(id)
                }
            }
            #expect(labelOrder.count == 6,
                           "Expected 6 labels (2 per default param), got \(labelOrder.count)")
            // Labels must be strictly ascending (left-to-right order).
            for i in 1 ..< labelOrder.count {
                #expect(labelOrder[i] > labelOrder[i - 1],
                                     "Labels must be ascending for left-to-right evaluation")
            }
        }
    }



    @Test
    func testDefaultArgStubBindsReceiverForExtensionFunctionDefault() throws {
        let ctx = try sharedDefaultArgsCtx()

        let module = try #require(ctx.kir)
        // Call site must use the $default stub
        let mainBody = try findKIRFunctionBody(named: "main4", in: module, interner: ctx.interner)
        let mainCallees = extractCallees(from: mainBody, interner: ctx.interner)
        #expect(mainCallees.contains("addDefault4$default"),
                      "Expected call to addDefault4$default stub, got: \(mainCallees)")

        // Stub must exist and include a receiver parameter
        let stubFunction = findAllKIRFunctions(in: module).compactMap { function -> KIRFunction? in
            return ctx.interner.resolve(function.name) == "addDefault4$default" ? function : nil
        }.first
        #expect(stubFunction != nil, "Expected addDefault4$default stub function")
        if let stub = stubFunction {
            // receiver + original param + mask = 3 params
            #expect(stub.params.count >= 3,
                                        "Stub should have receiver + param + mask, got \(stub.params.count)")
            let stubCallees = extractCallees(from: stub.body, interner: ctx.interner)
            #expect(stubCallees.contains("addDefault4"),
                          "Stub should call original addDefault4, got: \(stubCallees)")
        }
    }



    @Test
    func testDefaultArgCallerDoesNotLowerDefaultExpressionDirectly() throws {
        let ctx = try sharedDefaultArgsCtx()

        let module = try #require(ctx.kir)
        let mainBody = try findKIRFunctionBody(named: "main5", in: module, interner: ctx.interner)
        let mainCallees = extractCallees(from: mainBody, interner: ctx.interner)
        #expect(mainCallees.contains("compute5$default"),
                      "Caller should route to compute5$default, got: \(mainCallees)")

        // The caller (main5) body should NOT have a binary add — that belongs
        // in the stub's callee-context evaluation.
        let callerHasBinaryAdd = mainBody.contains { instruction in
            guard case let .binary(op, _, _, _) = instruction else { return false }
            return op == .add
        }
        #expect(!(callerHasBinaryAdd),
                       "Caller must not directly evaluate the default expression (binary add)")
    }


    // MARK: - Nested Return Propagation (P5-48)


    @Test
    func testNestedReturnInsideIfBranchEmitsReturnValueInstruction() throws {
        let ctx = try sharedDefaultArgsCtx()

        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "choose6", in: module, interner: ctx.interner)
        let returnValues = body.compactMap { instruction -> KIRExprID? in
            guard case let .returnValue(id) = instruction else { return nil }
            return id
        }
        #expect(returnValues.count >= 2, "Expected at least 2 returnValue instructions (if-branch + fallthrough), got \(returnValues.count)")
    }



    @Test
    func testNestedReturnInsideBothIfElseBranchesEmitsReturnValues() throws {
        let ctx = try sharedDefaultArgsCtx()

        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "pick7", in: module, interner: ctx.interner)
        let returnValues = body.compactMap { instruction -> KIRExprID? in
            guard case let .returnValue(id) = instruction else { return nil }
            return id
        }
        #expect(returnValues.count >= 2, "Expected at least 2 returnValue instructions (then-branch + else-branch), got \(returnValues.count)")
    }



    @Test
    func testNestedReturnInsideWhenBranchEmitsReturnValueInstruction() throws {
        let ctx = try sharedDefaultArgsCtx()

        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "describe8", in: module, interner: ctx.interner)
        let returnValues = body.compactMap { instruction -> KIRExprID? in
            guard case let .returnValue(id) = instruction else { return nil }
            return id
        }
        #expect(returnValues.count >= 2, "Expected at least 2 returnValue instructions for when-branch returns, got \(returnValues.count)")
    }



    @Test
    func testNestedReturnInIfBranchDoesNotEmitDeadCopyInstruction() throws {
        let ctx = try sharedDefaultArgsCtx()

        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "choose9", in: module, interner: ctx.interner)

        // After a returnValue instruction, there should be no copy to the if-result
        // that uses a Nothing-typed dead expression as source.
        var foundReturnInBranch = false
        var deadCopyAfterReturn = false
        for (index, instruction) in body.enumerated() {
            if case .returnValue = instruction {
                foundReturnInBranch = true
                // Check if the next non-label instruction is a copy
                var nextIndex = index + 1
                while nextIndex < body.count {
                    if case .label = body[nextIndex] {
                        nextIndex += 1
                        continue
                    }
                    if case .copy = body[nextIndex] {
                        deadCopyAfterReturn = true
                    }
                    break
                }
            }
        }
        #expect(foundReturnInBranch, "Expected returnValue in if-branch")
        #expect(!(deadCopyAfterReturn), "No dead copy should follow a returnValue instruction in a terminated branch")
    }



    @Test
    func testFunctionTypedMemberPropertyCallKeepsPropertyCalleeName() throws {
        let ctx = try sharedDefaultArgsCtx()

        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "use10", in: module, interner: ctx.interner)
        let callees = extractCallees(from: body, interner: ctx.interner)
        #expect(
            callees.contains("transform"),
            "Expected property callee name 'transform', got: \(callees)"
        )
        #expect(
            !(callees.contains("invoke")),
            "Function-typed property calls must not be rewritten to 'invoke'."
        )
    }

    // MARK: - Open/interface member default-argument virtual dispatch

    // An abstract interface member's `$default` bridge was never generated at
    // all: `CallSupportLowerer.collectFunctionDefaults` had no `.interfaceDecl`
    // case, so `Foo11.bar11`'s default-argument metadata never entered the
    // stub-generation mapping and callers routing through `bar11$default`
    // hit an undefined symbol at link time.
    @Test
    func testInterfaceMemberDefaultArgGeneratesStubWithItableDispatch() throws {
        let ctx = try sharedDefaultArgsCtx()

        let module = try #require(ctx.kir)
        let mainBody = try findKIRFunctionBody(named: "main11", in: module, interner: ctx.interner)
        let mainCallees = extractCallees(from: mainBody, interner: ctx.interner)
        #expect(mainCallees.contains("bar11$default"),
                      "Expected call to bar11$default stub, got: \(mainCallees)")

        let stubFunction = findAllKIRFunctions(in: module).first {
            ctx.interner.resolve($0.name) == "bar11$default"
        }
        #expect(stubFunction != nil, "Expected bar11$default stub function to be generated")
        guard let stub = stubFunction else { return }

        // The stub must be able to reach FooImpl11.bar11 through a dynamic
        // itable lookup -- before the fix, it only ever statically
        // re-invoked the abstract Foo11.bar11 declaration (which has no
        // runnable body). A static `.call(bar11)` also legitimately remains
        // in the stub as the fallback for a (Kotlin-illegal, not yet
        // diagnosed) `super.bar11(...)` caller that omits the default --
        // see CallSupportLowerer.superCallMaskBit -- guarded by a
        // `jumpIfEqual` that selects between the two at runtime.
        let hasRuntimeDispatchGuard = stub.body.contains { instruction in
            if case .jumpIfEqual = instruction { return true }
            return false
        }
        #expect(hasRuntimeDispatchGuard,
                      "Expected a runtime branch selecting between static (super) and virtual dispatch")

        let virtualDispatches = stub.body.compactMap { instruction -> KIRDispatchKind? in
            guard case let .virtualCall(_, callee, _, _, _, _, _, dispatch) = instruction else { return nil }
            return ctx.interner.resolve(callee) == "bar11" ? dispatch : nil
        }
        #expect(virtualDispatches.count == 1, "Expected exactly one virtual dispatch to bar11 in the stub")
        if case .itableDynamic = virtualDispatches.first {
            // Expected: the stub's own receiver type is the interface itself,
            // so the concrete implementer's itable slot is resolved at runtime.
        } else {
            Issue.record("Expected itableDynamic dispatch, got: \(String(describing: virtualDispatches.first))")
        }
    }

    // An open class member's `$default` bridge always statically re-invoked
    // the declaring class's own body (`originalSymbol`), bypassing vtable
    // dispatch. A subclass override was therefore silently skipped whenever
    // the call omitted a defaulted trailing argument.
    @Test
    func testOpenClassMemberDefaultArgGeneratesStubWithVtableDispatch() throws {
        let ctx = try sharedDefaultArgsCtx()

        let module = try #require(ctx.kir)
        let mainBody = try findKIRFunctionBody(named: "main12", in: module, interner: ctx.interner)
        let mainCallees = extractCallees(from: mainBody, interner: ctx.interner)
        #expect(mainCallees.contains("baz12$default"),
                      "Expected call to baz12$default stub, got: \(mainCallees)")

        let stubFunction = findAllKIRFunctions(in: module).first {
            ctx.interner.resolve($0.name) == "baz12$default"
        }
        #expect(stubFunction != nil, "Expected baz12$default stub function to be generated")
        guard let stub = stubFunction else { return }

        // A static `.call(baz12)` legitimately remains in the stub as the
        // fallback for a (Kotlin-illegal, not yet diagnosed)
        // `super.baz12(...)` caller that omits the default -- see
        // CallSupportLowerer.superCallMaskBit -- guarded by a `jumpIfEqual`
        // that selects between it and the virtual dispatch below at runtime.
        let hasRuntimeDispatchGuard = stub.body.contains { instruction in
            if case .jumpIfEqual = instruction { return true }
            return false
        }
        #expect(hasRuntimeDispatchGuard,
                      "Expected a runtime branch selecting between static (super) and virtual dispatch")

        let virtualDispatches = stub.body.compactMap { instruction -> KIRDispatchKind? in
            guard case let .virtualCall(_, callee, _, _, _, _, _, dispatch) = instruction else { return nil }
            return ctx.interner.resolve(callee) == "baz12" ? dispatch : nil
        }
        #expect(virtualDispatches.count == 1, "Expected exactly one virtual dispatch to baz12 in the stub")
        if case .vtable = virtualDispatches.first {
            // Expected: Base12 has a subtype (Derived12), so calls through the
            // stub must resolve via vtable at the receiver's runtime type.
        } else {
            Issue.record("Expected vtable dispatch, got: \(String(describing: virtualDispatches.first))")
        }
    }

}
#endif
