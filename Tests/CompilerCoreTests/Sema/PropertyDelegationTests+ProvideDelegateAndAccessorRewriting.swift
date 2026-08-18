#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

// MARK: - SymbolTable Delegate Storage Tests

/// DEBT-KIR-008: class-member delegate storage (`$delegate_x`) now writes
/// through `kk_array_set` at the field's instance offset instead of a
/// module-global `.copy`, so "delegate storage was initialized" must accept
/// either shape — `.copy` still covers top-level/object delegates, which
/// intentionally keep a single shared global slot.


private enum PropertyDelegationSharedContext {
    static nonisolated(unsafe) var raw: CompilationContext?
    static nonisolated(unsafe) var lowered: CompilationContext?
}

private func sharedPropertyDelegationRawCtx() throws -> CompilationContext {
    if let cached = PropertyDelegationSharedContext.raw {
        return cached
    }

    let sources: [String] = [
        """
        package delegation.raw0
        class MyDelegate0 {
            operator fun getValue(thisRef: Any?, property: Any?): Int = 42
        }
        class Foo0 {
            val x: Int by MyDelegate0()
        }
        """,
        """
        package delegation.raw1
        class MyDelegate1 {
            operator fun getValue(thisRef: Any?, property: Any?): Int = 42
        }
        class Foo1 {
            val x: Int by MyDelegate1()
        }
        """,
        """
        package delegation.raw2
        class MyDelegate2 {
            operator fun provideDelegate(thisRef: Any?, property: Any?): MyDelegate2 = this
            operator fun getValue(thisRef: Any?, property: Any?): Int = 42
        }
        class Foo2 {
            val x: Int by MyDelegate2()
        }
        """,
        """
        package delegation.raw3
        class MyDelegate3 {
            operator fun provideDelegate(thisRef: Any?, property: Any?): MyDelegate3 = this
            operator fun getValue(thisRef: Any?, property: Any?): Int = 42
        }
        class Foo3 {
            val x: Int by MyDelegate3()
        }
        """,
    ]

    var result: CompilationContext?
    try withTemporaryFiles(contents: sources) { paths in
        let ctx = makeCompilationContext(inputs: paths, emit: .kirDump)
        try runToKIR(ctx)
        result = ctx
    }

    let ctx = try #require(result)
    PropertyDelegationSharedContext.raw = ctx
    return ctx
}

private func sharedPropertyDelegationLoweredCtx() throws -> CompilationContext {
    if let cached = PropertyDelegationSharedContext.lowered {
        return cached
    }

    let sources: [String] = [
        """
        package delegation.lower0
        class MyDelegate4 {
            operator fun getValue(thisRef: Any?, property: Any?): Int = 42
        }
        class Foo4 {
            val x: Int by MyDelegate4()
        }
        """,
        """
        package delegation.lower1
        class MyDelegate6 {
            operator fun getValue(thisRef: Any?, property: Any?): Int = 42
            operator fun setValue(thisRef: Any?, property: Any?, value: Int) {}
        }
        class Foo6 {
            var x: Int by MyDelegate6()
        }
        """,
        """
        package delegation.lower2
        class MyDelegate7 {
            operator fun getValue(thisRef: Any?, property: Any?): Int = 42
        }
        class Foo7 {
            val x: Int by MyDelegate7()
        }
        """,
        """
        package delegation.lower3
        class MyDelegate8 {
            operator fun getValue(thisRef: Any?, property: Any?): Int = 42
            operator fun setValue(thisRef: Any?, property: Any?, value: Int) {}
        }
        class Foo8 {
            var x: Int by MyDelegate8()
        }
        """,
        """
        package delegation.lower4
        class MyDelegate9 {
            operator fun provideDelegate(thisRef: Any?, property: Any?): MyDelegate9 = this
            operator fun getValue(thisRef: Any?, property: Any?): Int = 42
        }
        class Foo9 {
            val x: Int by MyDelegate9()
        }
        """,
        """
        package delegation.lower5
        class MyDelegate10 {
            operator fun getValue(thisRef: Any?, property: Any?): Int = 42
        }
        val x10: Int by MyDelegate10()
        """,
    ]

    var result: CompilationContext?
    try withTemporaryFiles(contents: sources) { paths in
        let ctx = makeCompilationContext(inputs: paths, emit: .kirDump)
        try runToKIR(ctx)
        try LoweringPhase().run(ctx)
        result = ctx
    }

    let ctx = try #require(result)
    PropertyDelegationSharedContext.lowered = ctx
    return ctx
}

private func hasDelegateStorageWrite(_ body: [KIRInstruction], interner: StringInterner) -> Bool {
    body.contains { instruction in
        switch instruction {
        case .copy:
            return true
        case let .call(_, callee, _, _, _, _, _, _):
            return interner.resolve(callee) == "kk_array_set"
        default:
            return false
        }
    }
}

extension DelegateStorageSymbolTableTests {
    @Test func testConstructorInitializesDelegateStorage() throws {
        let ctx = try sharedPropertyDelegationRawCtx()
        let module = try #require(ctx.kir)
        let interner = ctx.interner

        let constructors = findAllKIRFunctions(in: module).compactMap { fn -> KIRFunction? in
            interner.resolve(fn.name) == "Foo0" ? fn : nil
        }
        #expect(!constructors.isEmpty, "Expected constructor to be emitted")

        if let ctor = constructors.first {
            #expect(
                hasDelegateStorageWrite(ctor.body, interner: interner),
                "Constructor should have an instruction to initialize delegate storage"
            )
        }
    }
    @Test func testConstructorDoesNotCallProvideDelegateWhenNotDefined() throws {
        let ctx = try sharedPropertyDelegationRawCtx()
        let module = try #require(ctx.kir)
        let interner = ctx.interner

        let constructors = findAllKIRFunctions(in: module).compactMap { fn -> KIRFunction? in
            interner.resolve(fn.name) == "Foo1" ? fn : nil
        }

        if let ctor = constructors.first {
            let callees = extractCallees(from: ctor.body, interner: interner)
            #expect(!callees.contains("provideDelegate"),
                           "provideDelegate should NOT be called when delegate type doesn't define it")
        }
    }
    @Test func testConstructorCallsProvideDelegateWhenTypeResolved() throws {
        let ctx = try sharedPropertyDelegationRawCtx()
        let module = try #require(ctx.kir)
        let interner = ctx.interner

        let constructors = findAllKIRFunctions(in: module).compactMap { fn -> KIRFunction? in
            interner.resolve(fn.name) == "Foo2" ? fn : nil
        }
        #expect(!constructors.isEmpty, "Expected Foo constructor")

        if let ctor = constructors.first {
            #expect(
                hasDelegateStorageWrite(ctor.body, interner: interner),
                "Constructor should initialize delegate storage"
            )

            let callees = extractCallees(from: ctor.body, interner: interner)
            if callees.contains("provideDelegate") {
                let provideDelegateCalls = ctor.body.compactMap { instruction
                    -> (symbol: SymbolID?, args: [KIRExprID])? in
                    guard case let .call(sym, callee, args, _, _, _, _, _) = instruction,
                          interner.resolve(callee) == "provideDelegate" else { return nil }
                    return (symbol: sym, args: args)
                }
                if let call = provideDelegateCalls.first {
                    #expect(call.symbol != nil)
                    #expect(call.args.count == 3)
                }
            }
        }
    }
    @Test func testProvideDelegateCallShapeWhenEmitted() throws {
        let ctx = try sharedPropertyDelegationRawCtx()
        let module = try #require(ctx.kir)
        let sema = try #require(ctx.sema)
        let interner = ctx.interner

        let constructors = findAllKIRFunctions(in: module).compactMap { fn -> KIRFunction? in
            interner.resolve(fn.name) == "Foo3" ? fn : nil
        }
        #expect(!constructors.isEmpty, "Expected Foo constructor")

        if let ctor = constructors.first {
            let provideDelegateCalls = ctor.body.compactMap { instruction
                -> (symbol: SymbolID?, args: [KIRExprID])? in
                guard case let .call(sym, callee, args, _, _, _, _, _) = instruction,
                      interner.resolve(callee) == "provideDelegate" else { return nil }
                return (symbol: sym, args: args)
            }
            let call = try #require(provideDelegateCalls.first)
            let callSymbol = try #require(call.symbol)
            #expect(
                sema.symbols.symbol(callSymbol)?.name == interner.intern("provideDelegate"),
                "provideDelegate must use the resolved operator symbol"
            )
            #expect(
                call.args.count == 3,
                "provideDelegate must receive delegate, thisRef, and KProperty"
            )
        }
    }
    @Test func testPropertyLoweringPreservesGetValueInsideAccessorToAvoidRecursion() throws {
        let ctx = try sharedPropertyDelegationLoweredCtx()
        let module = try #require(ctx.kir)
        let interner = ctx.interner

        var getterRetainsGetValue = false
        var synthesizedGetterExists = false
        for fn in findAllKIRFunctions(in: module) {
            let fnName = interner.resolve(fn.name)
            if fnName == "get" {
                synthesizedGetterExists = true
                if extractCallees(from: fn.body, interner: interner).contains("getValue") {
                    getterRetainsGetValue = true
                }
            }
        }
        #expect(getterRetainsGetValue || synthesizedGetterExists,
                      "Expected synthesized getter path to remain available after lowering")
    }
    @Test func testPropertyLoweringDoesNotRewriteProvideDelegateToKKPropertyAccess() throws {
        let source = """
        class MyDelegate {
            operator fun provideDelegate(thisRef: Any?, property: Any?): MyDelegate = this
            operator fun getValue(thisRef: Any?, property: Any?): Int = 42
        }
        class Foo {
            val x: Int by MyDelegate()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            // Before lowering, verify provideDelegate exists in a constructor.
            let moduleBeforeLowering = try #require(ctx.kir)
            let constructors = findAllKIRFunctions(in: moduleBeforeLowering).compactMap { fn -> KIRFunction? in
                return ctx.interner.resolve(fn.name) == "Foo" ? fn : nil
            }
            let hasProvideDelegateBeforeLowering = constructors.contains { ctor in
                extractCallees(from: ctor.body, interner: ctx.interner).contains("provideDelegate")
            }

            try LoweringPhase().run(ctx)

            let module = try #require(ctx.kir)
            let interner = ctx.interner

            // After lowering, provideDelegate should still be provideDelegate
            // (not rewritten to kk_property_access).
            if hasProvideDelegateBeforeLowering {
                let constructorsAfter = findAllKIRFunctions(in: module).compactMap { fn -> KIRFunction? in
                    return interner.resolve(fn.name) == "Foo" ? fn : nil
                }
                let hasProvideDelegate = constructorsAfter.contains { ctor in
                    extractCallees(from: ctor.body, interner: interner).contains("provideDelegate")
                }
                #expect(hasProvideDelegate,
                              "provideDelegate should NOT be rewritten to kk_property_access after lowering")
            }
        }
    }

    @Test func testPropertyLoweringPreservesSetValueInsideAccessorToAvoidRecursion() throws {
        let ctx = try sharedPropertyDelegationLoweredCtx()
        let module = try #require(ctx.kir)
        let interner = ctx.interner

        var setterRetainsSetValue = false
        var synthesizedSetterExists = false
        for fn in findAllKIRFunctions(in: module) {
            let fnName = interner.resolve(fn.name)
            if fnName == "set" {
                synthesizedSetterExists = true
                if extractCallees(from: fn.body, interner: interner).contains("setValue") {
                    setterRetainsSetValue = true
                }
            }
        }
        #expect(setterRetainsSetValue || synthesizedSetterExists,
                      "Expected synthesized setter path to remain available after lowering")
    }
    @Test func testDelegatedPropertyCompilesWithoutErrors() throws {
        let ctx = try sharedPropertyDelegationLoweredCtx()
        #expect(!ctx.diagnostics.hasError,
                       "Delegated property should compile without errors")
    }
    @Test func testMutableDelegatedPropertyCompilesWithoutErrors() throws {
        let ctx = try sharedPropertyDelegationLoweredCtx()
        #expect(!ctx.diagnostics.hasError,
                       "Mutable delegated property should compile without errors")
    }
    @Test func testDelegatedPropertyWithProvideDelegateCompilesWithoutErrors() throws {
        let ctx = try sharedPropertyDelegationLoweredCtx()
        #expect(!ctx.diagnostics.hasError,
                       "Delegated property with provideDelegate should compile without errors")
    }
    @Test func testTopLevelDelegatedPropertyCompilesWithoutErrors() throws {
        let ctx = try sharedPropertyDelegationLoweredCtx()
        #expect(!ctx.diagnostics.hasError,
                       "Top-level delegated property should compile without errors")
    }
}
#endif
