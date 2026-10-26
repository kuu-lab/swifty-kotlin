#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

// KUU-2953: enum member state lives in per-entry ordinal slots behind the
// `$enumConstructorProperty$` / `$enumPropertySetter$` helpers. The synthetic
// accessor emitted for a bound property reference (`this::value`) must call
// those helpers like the ordinary member read/write paths — the nominal
// field/global fallback reads a slot that is never written and yields null.
extension LoweringPassRegressionTests {
    @Test
    func testEnumEntryBoundPropertyReferenceAccessorReadsEnumHelper() throws {
        let source = """
        enum class X {
            B {
                override val value = "OK"
                val bmr = this::value.get()
                override fun foo() = bmr
            };
            abstract val value: String
            abstract fun foo(): String
        }

        fun main() {
            println(X.B.foo())
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "EnumEntryBoundPropertyRef",
                emit: .kirDump
            )
            try runToLowering(ctx)
            #expect(
                !ctx.diagnostics.hasError,
                "enum entry bound property reference should lower: \(ctx.diagnostics.diagnostics.map(\.message))"
            )

            let module = try #require(ctx.kir)
            let getterCallsHelper = findAllKIRFunctions(in: module).contains { function in
                ctx.interner.resolve(function.name) == "get"
                    && function.body.contains { instruction in
                        guard case let .call(_, callee, _, _, _, _, _, _) = instruction else { return false }
                        return ctx.interner.resolve(callee).hasPrefix("$enumConstructorProperty$")
                    }
            }
            #expect(getterCallsHelper)
        }
    }

    @Test
    func testMutableEnumConstructorPropertyReferenceWritesEnumHelper() throws {
        let source = """
        enum class M(var v: Int) {
            P(1), Q(2)
        }

        fun main() {
            M.P.v = 99
            val ref = M.Q::v
            ref.set(7)
            println(ref.get())
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "EnumMutableCtorPropertyRef",
                emit: .kirDump
            )
            try runToLowering(ctx)
            // Literal-only enums used to take the storage-free fast path and
            // never emit `$enumPropertySetter$v`; any `var` write then failed
            // the KIR verifier with an unresolved callee.
            #expect(
                !ctx.diagnostics.hasError,
                "mutable enum constructor property should keep setter helper: \(ctx.diagnostics.diagnostics.map(\.message))"
            )

            let module = try #require(ctx.kir)
            let functions = findAllKIRFunctions(in: module)
            #expect(functions.contains {
                ctx.interner.resolve($0.name).hasPrefix("$enumPropertySetter$")
            })
            let setterCallsHelper = functions.contains { function in
                ctx.interner.resolve(function.name) == "set"
                    && function.body.contains { instruction in
                        guard case let .call(_, callee, _, _, _, _, _, _) = instruction else { return false }
                        return ctx.interner.resolve(callee).hasPrefix("$enumPropertySetter$")
                    }
            }
            #expect(setterCallsHelper)
        }
    }
}
#endif
