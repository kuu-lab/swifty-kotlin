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
        let calls = kirCalls(to: .opIs, in: body, interner: ctx.interner)
        #expect(calls.count == 1)
        let token = try #require(calls.first?.arguments.last)
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
