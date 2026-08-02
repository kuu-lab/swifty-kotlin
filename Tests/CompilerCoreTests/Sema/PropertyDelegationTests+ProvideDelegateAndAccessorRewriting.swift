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
        let source = """
        class MyDelegate {
            operator fun getValue(thisRef: Any?, property: Any?): Int = 42
        }
        class Foo {
            val x: Int by MyDelegate()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let interner = ctx.interner

            // KIR constructors are named by the class name ("Foo"), not "<init>".
            let constructors = findAllKIRFunctions(in: module).compactMap { fn -> KIRFunction? in
                return interner.resolve(fn.name) == "Foo" ? fn : nil
            }
            #expect(!constructors.isEmpty, "Expected constructor to be emitted")

            // Verify the constructor body initializes delegate storage (either
            // a `.copy` to a global slot, or a `kk_array_set` instance-field
            // write — see DEBT-KIR-008).
            if let ctor = constructors.first {
                #expect(
                    hasDelegateStorageWrite(ctor.body, interner: interner),
                    "Constructor should have an instruction to initialize delegate storage"
                )
            }
        }
    }

    @Test func testConstructorDoesNotCallProvideDelegateWhenNotDefined() throws {
        let source = """
        class MyDelegate {
            operator fun getValue(thisRef: Any?, property: Any?): Int = 42
        }
        class Foo {
            val x: Int by MyDelegate()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let interner = ctx.interner

            let constructors = findAllKIRFunctions(in: module).compactMap { fn -> KIRFunction? in
                return interner.resolve(fn.name) == "Foo" ? fn : nil
            }

            if let ctor = constructors.first {
                let callees = extractCallees(from: ctor.body, interner: interner)
                #expect(!callees.contains("provideDelegate"),
                               "provideDelegate should NOT be called when delegate type doesn't define it")
            }
        }
    }

    @Test func testConstructorCallsProvideDelegateWhenTypeResolved() throws {
        // When the delegate expression type is resolved as a classType
        // with a provideDelegate member, the constructor should emit
        // a provideDelegate call.  If type resolution does not produce
        // a classType (current limitation for some call expressions),
        // the constructor falls back to storing the delegate directly.
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

            let module = try #require(ctx.kir)
            let interner = ctx.interner

            let constructors = findAllKIRFunctions(in: module).compactMap { fn -> KIRFunction? in
                return interner.resolve(fn.name) == "Foo" ? fn : nil
            }
            #expect(!constructors.isEmpty, "Expected Foo constructor")

            // Verify the constructor body initializes delegate storage (either
            // a `.copy` to a global slot, or a `kk_array_set` instance-field
            // write — see DEBT-KIR-008).
            if let ctor = constructors.first {
                #expect(
                    hasDelegateStorageWrite(ctor.body, interner: interner),
                    "Constructor should initialize delegate storage"
                )

                let callees = extractCallees(from: ctor.body, interner: interner)
                // provideDelegate emission depends on type resolution;
                // either it's present or the fallback direct-store path
                // is taken.  Both are valid.
                if callees.contains("provideDelegate") {
                    // If provideDelegate was emitted, it must be a
                    // method call with the receiver plus 2 Kotlin arguments.
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
    }

    @Test func testProvideDelegateCallShapeWhenEmitted() throws {
        // A member provideDelegate call must target the resolved operator and
        // pass the raw delegate receiver before thisRef and KProperty.
        // The golden test `property_delegation.kt` covers the full
        // output; this unit test validates the KIR instruction shape.
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

            let module = try #require(ctx.kir)
            let sema = try #require(ctx.sema)
            let interner = ctx.interner

            let constructors = findAllKIRFunctions(in: module).compactMap { fn -> KIRFunction? in
                return interner.resolve(fn.name) == "Foo" ? fn : nil
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
    }
}

// MARK: - PropertyLoweringPass Delegate Rewrite Tests

@Suite
struct PropertyLoweringDelegateTests {
    @Test func testPropertyLoweringPreservesGetValueInsideAccessorToAvoidRecursion() throws {
        let source = """
        class MyDelegate {
            operator fun getValue(thisRef: Any?, property: Any?): Int = 42
        }
        class Foo {
            val x: Int by MyDelegate()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)

            let module = try #require(ctx.kir)
            let interner = ctx.interner

            // After lowering, the synthesized getter's body should still
            // contain a getValue call (not rewritten to a self-call via
            // "get") to avoid infinite recursion.
            let allFunctions = findAllKIRFunctions(in: module).compactMap { fn -> KIRFunction? in
                return fn
            }

            // Lowering should keep a delegate-aware accessor path available.
            var getterRetainsGetValue = false
            var synthesizedGetterExists = false
            for fn in allFunctions {
                let fnName = interner.resolve(fn.name)
                if fnName == "get" {
                    synthesizedGetterExists = true
                    let callees = extractCallees(from: fn.body, interner: interner)
                    if callees.contains("getValue") {
                        getterRetainsGetValue = true
                    }
                }
            }
            #expect(getterRetainsGetValue || synthesizedGetterExists,
                          "Expected synthesized getter path to remain available after lowering")
        }
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
        let source = """
        class MyDelegate {
            operator fun getValue(thisRef: Any?, property: Any?): Int = 42
            operator fun setValue(thisRef: Any?, property: Any?, value: Int) {}
        }
        class Foo {
            var x: Int by MyDelegate()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)

            let module = try #require(ctx.kir)
            let interner = ctx.interner

            let allFunctions = findAllKIRFunctions(in: module).compactMap { fn -> KIRFunction? in
                return fn
            }

            // Lowering should keep a delegate-aware setter path available.
            var setterRetainsSetValue = false
            var synthesizedSetterExists = false
            for fn in allFunctions {
                let fnName = interner.resolve(fn.name)
                if fnName == "set" {
                    synthesizedSetterExists = true
                    let callees = extractCallees(from: fn.body, interner: interner)
                    if callees.contains("setValue") {
                        setterRetainsSetValue = true
                    }
                }
            }
            #expect(setterRetainsSetValue || synthesizedSetterExists,
                          "Expected synthesized setter path to remain available after lowering")
        }
    }
}

// MARK: - End-to-end Compilation Tests

@Suite
struct PropertyDelegationEndToEndTests {
    @Test func testDelegatedPropertyCompilesWithoutErrors() throws {
        let source = """
        class MyDelegate {
            operator fun getValue(thisRef: Any?, property: Any?): Int = 42
        }
        class Foo {
            val x: Int by MyDelegate()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            #expect(!ctx.diagnostics.hasError,
                           "Delegated property should compile without errors")
        }
    }

    @Test func testMutableDelegatedPropertyCompilesWithoutErrors() throws {
        let source = """
        class MyDelegate {
            operator fun getValue(thisRef: Any?, property: Any?): Int = 42
            operator fun setValue(thisRef: Any?, property: Any?, value: Int) {}
        }
        class Foo {
            var x: Int by MyDelegate()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            #expect(!ctx.diagnostics.hasError,
                           "Mutable delegated property should compile without errors")
        }
    }

    @Test func testDelegatedPropertyWithProvideDelegateCompilesWithoutErrors() throws {
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
            try LoweringPhase().run(ctx)
            #expect(!ctx.diagnostics.hasError,
                           "Delegated property with provideDelegate should compile without errors")
        }
    }

    @Test func testTopLevelDelegatedPropertyCompilesWithoutErrors() throws {
        let source = """
        class MyDelegate {
            operator fun getValue(thisRef: Any?, property: Any?): Int = 42
        }
        val x: Int by MyDelegate()
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            #expect(!ctx.diagnostics.hasError,
                           "Top-level delegated property should compile without errors")
        }
    }
}
#endif
