#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Foundation
import Testing
import TestStdlibCache

@Suite
struct DelegatedObjectMemberPropertyReferenceTests {
    /// KUU-3803: a bound `O::member` reference on a singleton `object`
    /// delegated `var` crashed with SIGSEGV — the generated KProperty
    /// wrapper invoked the real delegated accessor one argument short.
    /// KSP-505 keeps the reference receiver-free because *stored* object
    /// properties read a global slot, but a delegated accessor keeps its
    /// dispatch-receiver (`t`) parameter for the `getValue`/`setValue`
    /// forward, so the wrapper must load the singleton and pass it.
    @Test
    func objectDelegatedReferencePassesSingletonReceiverToAccessors() throws {
        TestStdlibCache.shared.prepare()
        let ctx = makeContextFromSource(
            """
            object Delegate {
                operator fun getValue(t: Any?, p: kotlin.reflect.KProperty<*>): String = ""
                operator fun setValue(t: Any?, p: kotlin.reflect.KProperty<*>, v: String) {}
            }
            object O { var member: String by Delegate }
            fun main() { O::member.set("") }
            """,
            allowDefaultStdlibLibrary: true
        )
        try runToLowering(ctx)
        try #require(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let module = try #require(ctx.kir)
        let sema = try #require(ctx.sema)
        let objectSymbol = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern("O")]))
        let propertySymbol = try #require(sema.symbols.lookup(
            fqName: ["O", "member"].map(ctx.interner.intern)
        ))
        let getterAccessor = SyntheticSymbolScheme.propertyGetterAccessorSymbol(for: propertySymbol)
        let setterAccessor = SyntheticSymbolScheme.propertySetterAccessorSymbol(for: propertySymbol)

        /// The symbol a call argument's `constValue` materializes, when it is
        /// a `symbolRef` literal (the singleton handle for the owner arg).
        func symbolMaterialized(by expr: KIRExprID, in body: [KIRInstruction]) -> SymbolID? {
            for instruction in body {
                if case let .constValue(result, .symbolRef(symbol)) = instruction, result == expr {
                    return symbol
                }
            }
            return nil
        }

        let functions = findAllKIRFunctions(in: module)

        let setterCalls = functions.flatMap { function in
            kirCalls(to: setterAccessor, in: function.body).map { ($0, function.body) }
        }
        let singletonSetterCall = setterCalls.first { call, body in
            call.arguments.count == 2
                && call.arguments.first.flatMap { symbolMaterialized(by: $0, in: body) } == objectSymbol
        }
        #expect(
            singletonSetterCall != nil,
            "the wrapper `set` must call the delegated setter as (singleton, value)"
        )
        #expect(
            setterCalls.allSatisfy { call, _ in call.arguments.count == 2 },
            "a delegated setter always wants (receiver, value) — no arity-short call site may remain"
        )

        let getterCalls = functions.flatMap { function in
            kirCalls(to: getterAccessor, in: function.body).map { ($0, function.body) }
        }
        let singletonGetterCall = getterCalls.first { call, body in
            call.arguments.count == 1
                && call.arguments.first.flatMap { symbolMaterialized(by: $0, in: body) } == objectSymbol
        }
        #expect(
            singletonGetterCall != nil,
            "the wrapper `get` must call the delegated getter as (singleton)"
        )
    }
}
#endif
