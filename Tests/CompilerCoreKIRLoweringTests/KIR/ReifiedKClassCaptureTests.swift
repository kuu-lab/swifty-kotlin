#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

struct ReifiedKClassCaptureTests {
    @Test
    func classLiteralUsesCapturedReifiedTokenInsideLambda() throws {
        let fixture = makeKIRDirectLoweringFixture()
        let typeParameter = defineSemanticSymbol(
            in: fixture,
            kind: .typeParameter,
            fqName: ["pkg", "inlineName", "T"],
            flags: [.reifiedTypeParameter]
        )
        let tokenSymbol = SyntheticSymbolScheme.reifiedTypeTokenSymbol(for: typeParameter)
        let tokenPair = fixture.kirArena.appendTemporary(type: fixture.types.anyType)
        let capturedToken = fixture.kirArena.appendTemporary(type: fixture.types.intType)
        fixture.driver.ctx.setLocalValue(capturedToken, for: tokenSymbol)

        let classType = fixture.types.make(.typeParam(TypeParamType(symbol: typeParameter)))
        let expression = fixture.astArena.appendExpr(.nameRef(fixture.interner.intern("T"), makeRange()))
        var instructions = [
            KIRInstruction.call(
                callee: fixture.interner.intern("__kk_pair_first"),
                arguments: [tokenPair],
                result: capturedToken,
                canThrow: false
            ),
        ]

        _ = fixture.driver.callLowerer.lowerKClassReflectMemberCall(
            expression,
            classRefTargetType: classType,
            memberName: "simpleName",
            sema: fixture.sema,
            arena: fixture.kirArena,
            interner: fixture.interner,
            instructions: &instructions
        )

        let createCall = try #require(instructions.first { instruction in
            guard case let .call(_, callee, _, _, _, _, _, _) = instruction else { return false }
            return fixture.interner.resolve(callee) == "__kk_kclass_create"
        })
        guard case let .call(_, _, arguments, _, _, _, _, _) = createCall else {
            Issue.record("Expected __kk_kclass_create call")
            return
        }
        #expect(arguments.first == capturedToken)
    }

    @Test
    func standaloneClassLiteralUsesTokenRestoredFromLambdaCapture() throws {
        let ctx = makeContextFromSource("""
        private class OK2
        private inline fun invoke(block: () -> String): String = block()
        private inline fun <reified T : Any> name(): String =
            invoke { T::class.simpleName!! }
        fun main() { println(name<OK2>()) }
        """)
        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let module = try #require(ctx.kir)
        // KUU-4018: reified `T::class` lowers to `__kk_kclass_create_array` —
        // the captured component descriptor feeds
        // `__kk_array_component_element`, which yields 0 for non-array T and
        // the element descriptor when T resolves to `Array<E>`.
        let lambda = try #require(findAllKIRFunctions(in: module).first { function in
            let calls = kirCalls(in: function.body)
            return calls.contains { ctx.interner.resolve($0.callee) == "__kk_pair_first" }
                && calls.contains { $0.callee == KIRRuntimeFunction.kClassCreateArray.name(in: ctx.interner) }
        })
        let calls = kirCalls(in: lambda.body)
        let restore = try #require(calls.first { ctx.interner.resolve($0.callee) == "__kk_pair_first" })
        let create = try #require(calls.first { $0.callee == KIRRuntimeFunction.kClassCreateArray.name(in: ctx.interner) })
        let capturedToken = try #require(restore.result)
        #expect(create.arguments.first == capturedToken)
        #expect(calls.contains {
            $0.callee == KIRRuntimeFunction.arrayComponentElement.name(in: ctx.interner)
        })
    }
}
#endif
