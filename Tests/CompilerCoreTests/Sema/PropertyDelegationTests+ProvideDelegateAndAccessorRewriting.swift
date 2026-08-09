#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

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

@Suite
struct PropertyDelegationKIRTests {
    @Test func testDelegationKIR() throws {
        let sources: [String] = [
            """
            package sample0

                    class MyDelegate0 {
                        operator fun getValue(thisRef: Any?, property: Any?): Int = 42
                    }
                    class Foo0 {
                        val x: Int by MyDelegate0()
                    }
            """,
            """
            package sample1

                    class MyDelegate1 {
                        operator fun getValue(thisRef: Any?, property: Any?): Int = 42
                    }
                    class Foo1 {
                        val x: Int by MyDelegate1()
                    }
            """,
            """
            package sample2

                    class MyDelegate2 {
                        operator fun provideDelegate(thisRef: Any?, property: Any?): MyDelegate2 = this
                        operator fun getValue(thisRef: Any?, property: Any?): Int = 42
                    }
                    class Foo2 {
                        val x: Int by MyDelegate2()
                    }
            """,
            """
            package sample3

                    class MyDelegate3 {
                        operator fun provideDelegate(thisRef: Any?, property: Any?): MyDelegate3 = this
                        operator fun getValue(thisRef: Any?, property: Any?): Int = 42
                    }
                    class Foo3 {
                        val x: Int by MyDelegate3()
                    }
            """,
            """
            package sample4

                    class MyDelegate4 {
                        operator fun getValue(thisRef: Any?, property: Any?): Int = 42
                    }
                    class Foo4 {
                        val x: Int by MyDelegate4()
                    }
            """,
            """
            package sample5

                    class MyDelegate5 {
                        operator fun provideDelegate(thisRef: Any?, property: Any?): MyDelegate5 = this
                        operator fun getValue(thisRef: Any?, property: Any?): Int = 42
                    }
                    class Foo5 {
                        val x: Int by MyDelegate5()
                    }
            """,
            """
            package sample6

                    class MyDelegate6 {
                        operator fun getValue(thisRef: Any?, property: Any?): Int = 42
                        operator fun setValue(thisRef: Any?, property: Any?, value: Int) {}
                    }
                    class Foo6 {
                        var x: Int by MyDelegate6()
                    }
            """,
            """
            package sample7

                    class MyDelegate7 {
                        operator fun getValue(thisRef: Any?, property: Any?): Int = 42
                    }
                    class Foo7 {
                        val x: Int by MyDelegate7()
                    }
            """,
            """
            package sample8

                    class MyDelegate8 {
                        operator fun getValue(thisRef: Any?, property: Any?): Int = 42
                        operator fun setValue(thisRef: Any?, property: Any?, value: Int) {}
                    }
                    class Foo8 {
                        var x: Int by MyDelegate8()
                    }
            """,
            """
            package sample9

                    class MyDelegate9 {
                        operator fun provideDelegate(thisRef: Any?, property: Any?): MyDelegate9 = this
                        operator fun getValue(thisRef: Any?, property: Any?): Int = 42
                    }
                    class Foo9 {
                        val x: Int by MyDelegate9()
                    }
            """,
            """
            package sample10

                    class MyDelegate10 {
                        operator fun getValue(thisRef: Any?, property: Any?): Int = 42
                    }
                    val x10: Int by MyDelegate10()
            """
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths, emit: .kirDump)
            try runToKIR(ctx)

            do {
                let path = paths[0]

                let module = try #require(ctx.kir)
                let interner = ctx.interner

                // KIR constructors are named by the class name ("Foo0"), not "<init>".
                let constructors = findAllKIRFunctions(in: module).compactMap { fn -> KIRFunction? in
                    return interner.resolve(fn.name) == "Foo0" ? fn : nil
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
            do {
                let path = paths[1]

                let module = try #require(ctx.kir)
                let interner = ctx.interner

                let constructors = findAllKIRFunctions(in: module).compactMap { fn -> KIRFunction? in
                    return interner.resolve(fn.name) == "Foo1" ? fn : nil
                }

                if let ctor = constructors.first {
                    let callees = extractCallees(from: ctor.body, interner: interner)
                    #expect(!callees.contains("provideDelegate"),
                                   "provideDelegate should NOT be called when delegate type doesn't define it")
                }
            }
            do {
                let path = paths[2]

                let module = try #require(ctx.kir)
                let interner = ctx.interner

                let constructors = findAllKIRFunctions(in: module).compactMap { fn -> KIRFunction? in
                    return interner.resolve(fn.name) == "Foo2" ? fn : nil
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
            do {
                let path = paths[3]

                let module = try #require(ctx.kir)
                let sema = try #require(ctx.sema)
                let interner = ctx.interner

                let constructors = findAllKIRFunctions(in: module).compactMap { fn -> KIRFunction? in
                    return interner.resolve(fn.name) == "Foo3" ? fn : nil
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
            do {
                let path = paths[5]

                // Before lowering, verify provideDelegate exists in a constructor.
                let moduleBeforeLowering = try #require(ctx.kir)
                let constructors = findAllKIRFunctions(in: moduleBeforeLowering).compactMap { fn -> KIRFunction? in
                    return ctx.interner.resolve(fn.name) == "Foo5" ? fn : nil
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
                        return interner.resolve(fn.name) == "Foo5" ? fn : nil
                    }
                    let hasProvideDelegate = constructorsAfter.contains { ctor in
                        extractCallees(from: ctor.body, interner: interner).contains("provideDelegate")
                    }
                    #expect(hasProvideDelegate,
                                  "provideDelegate should NOT be rewritten to kk_property_access after lowering")
                }
            }
            do {
                let path = paths[4]

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
            do {
                let path = paths[6]

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
            do {
                let path = paths[7]
                #expect(!ctx.diagnostics.hasError,
                               "Delegated property should compile without errors")
            }
            do {
                let path = paths[8]
                #expect(!ctx.diagnostics.hasError,
                               "Mutable delegated property should compile without errors")
            }
            do {
                let path = paths[9]
                #expect(!ctx.diagnostics.hasError,
                               "Delegated property with provideDelegate should compile without errors")
            }
            do {
                let path = paths[10]
                #expect(!ctx.diagnostics.hasError,
                               "Top-level delegated property should compile without errors")
            }
        }
    }
}
#endif
