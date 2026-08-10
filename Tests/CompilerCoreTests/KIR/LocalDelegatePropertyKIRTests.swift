#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// KSP-CAP-007 / BUG-014: local `by`-delegated declarations (`fun f() { val x by Prop() }`)
/// used to bind `x` straight to the delegate instance's own KIR value, never calling the
/// resolved `getValue`/`setValue` operator — see ExprLowerer+ControlFlowAndBlocks.swift's
/// `.localDecl`/`.localAssign` cases. Member and top-level delegated properties were
/// unaffected (they already route through a synthesized getter/setter accessor); only the
/// local-declaration path skipped the call entirely, regardless of the delegate's return type.
@Suite
struct LocalDelegatePropertyKIRTests {
    @Test func testLocalDelegatePropertyKIR() throws {
        let sources = [
            """
            package sample0
            class IntProp0 {
                operator fun getValue(thisRef: Any?, property: Any?): Int = 42
            }
            fun main0() {
                val x by IntProp0()
                println(x)
            }
            """,
            """
            package sample1
            class IntProp1 {
                operator fun getValue(thisRef: Any?, property: Any?): Int = 42
            }
            fun main1() {
                val x by IntProp1()
                println(x)
            }
            """,
            """
            package sample2
            class IntProp2 {
                var backing: Int = 0
                operator fun getValue(thisRef: Any?, property: Any?): Int = backing
                operator fun setValue(thisRef: Any?, property: Any?, value: Int) {
                    backing = value
                }
            }
            fun main2() {
                var x by IntProp2()
                x = 100
                println(x)
            }
            """,
            """
            package sample3
            class IntProp3 {
                operator fun getValue(thisRef: Any?, property: Any?): Int = 42
            }
            fun main3() {
                val x by IntProp3()
                println(x + 1)
            }
            """,
            """
            package sample4
            class ValidatedDelegate4(private val value: String) {
                operator fun getValue(thisRef: Any?, property: Any?): String = value
            }
            class DelegateFactory4 {
                operator fun provideDelegate(thisRef: Any?, prop: Any?): ValidatedDelegate4 = ValidatedDelegate4("ok")
            }
            fun main4() {
                val name by DelegateFactory4()
                println(name)
            }
            """,
            """
            package sample5
            class ValidatedDelegate5(private val value: String) {
                operator fun getValue(thisRef: Any?, property: Any?): String = value
            }
            class DelegateFactory5 {
                operator fun provideDelegate(thisRef: Any?, prop: Any?): ValidatedDelegate5 = ValidatedDelegate5("ok")
            }
            fun main5() {
                val name by DelegateFactory5()
                println(name)
            }
            """,
            """
            package sample6
            class IntBox6(private var stored: Int) {
                operator fun getValue(thisRef: Any?, property: Any?): Int = stored
                operator fun setValue(thisRef: Any?, property: Any?, value: Int) { stored = value }
            }
            class IntBoxFactory6(private val initial: Int) {
                operator fun provideDelegate(thisRef: Any?, prop: Any?): IntBox6 = IntBox6(initial)
            }
            fun main6() {
                var counter by IntBoxFactory6(10)
                counter = 42
                println(counter)
            }
            """,
            """
            package sample7
            fun main7() {
                val s by lazy { "hello" }
                println(s.length)
            }
            """,
            """
            package sample8
            fun main8() {
                val x by lazy { 42 }
                val f = { x }
                println(f())
            }
            """,
            """
            package sample9
            fun main9() {
                val x by lazy { 42 }
                println("before")
                println(x)
            }
            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths, emit: .kirDump)
            try runToKIR(ctx)

            let diagnosticMessages = ctx.diagnostics.diagnostics.map { $0.message }
            #expect(!ctx.diagnostics.hasError, "\(diagnosticMessages)")

            let module = try #require(ctx.kir)
            let interner = ctx.interner

            do {
                let body = try findKIRFunctionBody(named: "main0", in: module, interner: interner)
                let callees = extractCallees(from: body, interner: interner)
                #expect(callees.contains("getValue"), "got: \(callees)")
            }

            do {
                let body = try findKIRFunctionBody(named: "main1", in: module, interner: interner)

                var getValueResult: KIRExprID?
                var lastCallArguments: [KIRExprID] = []
                for instruction in body {
                    guard case let .call(_, callee, arguments, result, _, _, _, _) = instruction else { continue }
                    if interner.resolve(callee) == "getValue" {
                        getValueResult = result
                    }
                    lastCallArguments = arguments
                }

                let resolvedGetValueResult = try #require(getValueResult, "expected a getValue call in main1")
                #expect(
                    lastCallArguments.contains(resolvedGetValueResult),
                    "println should be called with getValue's result, not the Prop() instance itself"
                )
            }

            do {
                let body = try findKIRFunctionBody(named: "main2", in: module, interner: interner)
                let callees = extractCallees(from: body, interner: interner)
                #expect(callees.contains("setValue"), "got: \(callees)")
                #expect(callees.filter { $0 == "getValue" }.count >= 2, "got: \(callees)")
            }

            do {
                let body = try findKIRFunctionBody(named: "main4", in: module, interner: interner)
                let callees = extractCallees(from: body, interner: interner)
                #expect(callees.contains("provideDelegate"), "got: \(callees)")
                #expect(callees.contains("getValue"), "got: \(callees)")
            }

            do {
                let body = try findKIRFunctionBody(named: "main5", in: module, interner: interner)

                var provideDelegateResult: KIRExprID?
                var getValueArguments: [KIRExprID] = []
                for instruction in body {
                    guard case let .call(_, callee, arguments, result, _, _, _, _) = instruction else { continue }
                    switch interner.resolve(callee) {
                    case "provideDelegate":
                        provideDelegateResult = result
                    case "getValue":
                        getValueArguments = arguments
                    default:
                        break
                    }
                }

                let resolvedProvideResult = try #require(provideDelegateResult, "expected a provideDelegate call in main5")
                #expect(
                    getValueArguments.first == resolvedProvideResult,
                    "getValue's receiver must be provideDelegate's result"
                )
            }

            do {
                let body = try findKIRFunctionBody(named: "main6", in: module, interner: interner)
                let callees = extractCallees(from: body, interner: interner)
                #expect(callees.contains("provideDelegate"), "got: \(callees)")
                #expect(callees.contains("setValue"), "got: \(callees)")
            }

            do {
                var sawGetValue = false
                module.arena.transformFunctions { function in
                    for instruction in function.body {
                        guard case let .call(_, callee, _, _, _, _, _, _) = instruction else { continue }
                        if interner.resolve(callee) == "kk_lazy_get_value" { sawGetValue = true }
                    }
                    return function
                }
                #expect(sawGetValue, "a lambda reading a captured lazy local should call kk_lazy_get_value")
            }

            do {
                let body = try findKIRFunctionBody(named: "main9", in: module, interner: interner)
                let callees = extractCallees(from: body, interner: interner)
                let createIndex = try #require(callees.firstIndex(of: "lazy"), "got: \(callees)")
                let getValueIndex = try #require(callees.firstIndex(of: "kk_lazy_get_value"), "got: \(callees)")
                let printIndices = callees.indices.filter { callees[$0].hasPrefix("kk_println") }
                let firstPrintIndex = try #require(printIndices.first)
                #expect(createIndex < firstPrintIndex)
                #expect(getValueIndex > firstPrintIndex)
            }
        }
    }

    @Test func testLocalDelegatePropertyLowering() throws {
        let sources = [
            """
            package sample10
            fun main10() {
                val x by lazy { 42 }
                println(x)
                println(x)
            }
            """,
            """
            package sample11
            import kotlin.properties.Delegates
            fun main11() {
                var y by Delegates.observable(1) { _, old, new -> println("$old -> $new") }
                y = 5
                println(y)
            }
            """,
            """
            package sample12
            import kotlin.properties.Delegates
            fun main12() {
                var w by Delegates.notNull<Int>()
                w = 3
                println(w)
            }
            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths, emit: .kirDump)
            try runToLowering(ctx)

            let diagnosticMessages = ctx.diagnostics.diagnostics.map { $0.message }
            #expect(!ctx.diagnostics.hasError, "\(diagnosticMessages)")

            let module = try #require(ctx.kir)
            let interner = ctx.interner

            do {
                let body = try findKIRFunctionBody(named: "main10", in: module, interner: interner)
                let callees = extractCallees(from: body, interner: interner)
                #expect(callees.contains("kk_lazy_create"), "got: \(callees)")
                #expect(callees.filter { $0 == "kk_lazy_get_value" }.count == 2, "got: \(callees)")

                var derivedValues: Set<KIRExprID> = []
                var lastCallArguments: [KIRExprID] = []
                for instruction in body {
                    guard case let .call(_, callee, arguments, result, _, _, _, _) = instruction else { continue }
                    if interner.resolve(callee) == "kk_lazy_get_value", let result {
                        derivedValues.insert(result)
                    } else if let result, arguments.contains(where: { derivedValues.contains($0) }) {
                        derivedValues.insert(result)
                    }
                    lastCallArguments = arguments
                }
                #expect(!derivedValues.isEmpty)
                #expect(lastCallArguments.contains(where: { derivedValues.contains($0) }))
            }

            do {
                let body = try findKIRFunctionBody(named: "main11", in: module, interner: interner)
                let callees = extractCallees(from: body, interner: interner)
                #expect(callees.contains("kk_observable_create"), "got: \(callees)")
                #expect(callees.contains("kk_observable_set_value"), "got: \(callees)")
                #expect(callees.contains("kk_observable_get_value"), "got: \(callees)")
                #expect(!callees.contains("observable"), "got: \(callees)")
            }

            do {
                let body = try findKIRFunctionBody(named: "main12", in: module, interner: interner)
                let callees = extractCallees(from: body, interner: interner)
                #expect(callees.contains("kk_notNull_create"), "got: \(callees)")
                #expect(callees.contains("kk_notNull_set_value"), "got: \(callees)")
                #expect(callees.contains("kk_notNull_get_value"), "got: \(callees)")
            }
        }
    }
}
#endif
