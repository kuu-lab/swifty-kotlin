@testable import CompilerCore
import Testing

@Suite
struct FunctionTypeIsCheckLoweringTests {
    @Test(arguments: [false, true], ["is", "!is", "when-is", "when-!is"])
    func testKnownFunctionChecksOnlyCheckNullability(nullableTarget: Bool, context: String) throws {
        let target = nullableTarget ? "((Int) -> Int)?" : "(Int) -> Int"
        let expression: String
        switch context {
        case "when-is": expression = "when (x) { is \(target) -> true; else -> false }"
        case "when-!is": expression = "when (x) { !is \(target) -> true; else -> false }"
        default: expression = "x \(context) \(target)"
        }
        let ctx = makeContextFromSource("fun check(x: ((Int) -> Int)?): Boolean = \(expression)")
        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError)
        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "check", in: module, interner: ctx.interner)
        let calls = body.compactMap { instruction -> KIRExprID? in
            guard case let .call(_, callee, arguments, _, _, _, _, _) = instruction,
                  ctx.interner.resolve(callee) == "kk_op_is"
            else { return nil }
            return arguments.last
        }
        #expect(calls.count == 1)
        let token = try #require(calls.first)
        let expected = RuntimeTypeCheckToken.encode(base: RuntimeTypeCheckToken.anyBase, nullable: nullableTarget)
        #expect(module.arena.expr(token) == .intLiteral(expected))
    }

    @Test
    func testUnknownFunctionSignatureRetainsItsRuntimeToken() {
        let fixture = makeKIRDirectLoweringFixture()
        let target = fixture.types.make(.functionType(FunctionType(
            receiver: nil,
            params: [fixture.types.intType],
            returnType: fixture.types.intType,
            isSuspend: false,
            nullability: .nonNull
        )))
        #expect(fixture.driver.exprLowerer.runtimeIsCheckTargetType(
            subjectType: fixture.types.anyType,
            targetType: target,
            sema: fixture.sema
        ) == target)
    }
}
