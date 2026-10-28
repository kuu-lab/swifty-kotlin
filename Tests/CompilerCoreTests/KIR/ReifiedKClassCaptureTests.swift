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
            ast: fixture.ast,
            sema: fixture.sema,
            arena: fixture.kirArena,
            interner: fixture.interner,
            propertyConstantInitializers: [:],
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
}
#endif
