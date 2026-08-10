#if canImport(Testing)
@testable import CompilerCore
import Testing

// `.name`/`.ordinal` on an enum-typed receiver that isn't a literal entry
// reference (`Direction.NORTH.name`) or constant-foldable local used to lower
// to an unresolved external call literally named "name"/"ordinal" with the
// receiver silently dropped from its argument list -- it never linked
// ("Undefined symbols ... _name"). Root cause: `name`/`ordinal` are registered
// as synthetic .property symbols on kotlin.Enum<T> (HeaderHelpers+SyntheticEnumStubs.swift),
// not real .function declarations, so neither normal call-binding resolution
// nor CallLowerer's recovery/fallback path ever attaches a usable chosenCallee,
// and appendReceiverToMemberArguments had no case for "name"/"ordinal" to
// prepend the receiver anyway.
extension LoweringPassRegressionTests {
    @Test
    func testEnumNameAndOrdinalDynamicReceivers() throws {
        let sources = [
            """
            enum class Direction0 { NORTH0, SOUTH0 }
            fun printName0(d: Direction0) {
                println(d.name)
            }
            fun main0() {
                printName0(Direction0.NORTH0)
            }
            """,
            """
            enum class Direction1 { NORTH1, SOUTH1 }
            fun printOrdinal1(d: Direction1) {
                println(d.ordinal)
            }
            fun main1() {
                printOrdinal1(Direction1.SOUTH1)
            }
            """,
            """
            enum class Direction2 { NORTH2, SOUTH2 }
            fun main2() {
                listOf(Direction2.NORTH2, Direction2.SOUTH2).forEach { d -> println(d.name) }
            }
            """,
            """
            enum class Direction3 { NORTH, SOUTH }
            fun main3() {
                println(Direction3.NORTH.name)
            }
            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths, moduleName: "EnumNameOrdinalDynamicReceiver", emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            #expect(!ctx.diagnostics.hasError)

            let module = try #require(ctx.kir)

            // sample0: name on function parameter rewrites to $enumOrdinalToName(receiver)
            do {
                let body = try findKIRFunctionBody(named: "printName0", in: module, interner: ctx.interner)
                let callees = extractCallees(from: body, interner: ctx.interner)

                #expect(!callees.contains("name"),
                        "the raw unresolved \"name\" call must be rewritten away; callees: \(callees)")
                #expect(callees.contains("$enumOrdinalToName"),
                        "expected a rewrite to $enumOrdinalToName; callees: \(callees)")

                let helperCalls = body.compactMap { instruction -> Int? in
                    guard case let .call(_, callee, arguments, _, _, _, _, _) = instruction,
                          ctx.interner.resolve(callee) == "$enumOrdinalToName"
                    else { return nil }
                    return arguments.count
                }
                #expect(helperCalls == [1], "the receiver must survive as the helper's sole argument; got: \(helperCalls)")
            }

            // sample1: ordinal on function parameter rewrites to kk_unbox_int(receiver)
            do {
                let body = try findKIRFunctionBody(named: "printOrdinal1", in: module, interner: ctx.interner)
                let callees = extractCallees(from: body, interner: ctx.interner)

                #expect(!callees.contains("ordinal"),
                        "the raw unresolved \"ordinal\" call must be rewritten away; callees: \(callees)")

                let unboxCalls = body.compactMap { instruction -> Int? in
                    guard case let .call(_, callee, arguments, _, _, _, _, _) = instruction,
                          ctx.interner.resolve(callee) == "kk_unbox_int"
                    else { return nil }
                    return arguments.count
                }
                #expect(unboxCalls == [1], "expected a single kk_unbox_int(receiver) call; got: \(unboxCalls)")
            }

            // sample2: name on collection HOF lambda parameter rewrites to $enumOrdinalToName
            do {
                let allCallees = findAllKIRFunctions(in: module).flatMap { function in
                    extractCallees(from: function.body, interner: ctx.interner)
                }

                #expect(!allCallees.contains("name"),
                        "the raw unresolved \"name\" call must be rewritten away; callees: \(allCallees)")
                #expect(allCallees.contains("$enumOrdinalToName"),
                        "expected a rewrite to $enumOrdinalToName; callees: \(allCallees)")
            }

            // sample3: literal entry receiver stays on the per-entry helper fast path
            do {
                let body = try findKIRFunctionBody(named: "main3", in: module, interner: ctx.interner)
                let callees = extractCallees(from: body, interner: ctx.interner)

                #expect(!callees.contains("$enumOrdinalToName"),
                        "a literal entry receiver should stay on the per-entry helper fast path; callees: \(callees)")
                #expect(!callees.contains("name"), "callees: \(callees)")
                #expect(callees.contains("NORTH$enumName"),
                        "expected the literal fast path's per-entry helper call; callees: \(callees)")

                let nameHelperBody = try findKIRFunctionBody(named: "NORTH$enumName", in: module, interner: ctx.interner)
                let stringLiterals = nameHelperBody.compactMap { instruction -> String? in
                    guard case let .constValue(_, value) = instruction, case let .stringLiteral(s) = value else { return nil }
                    return ctx.interner.resolve(s)
                }
                #expect(stringLiterals.contains("NORTH"), "expected NORTH$enumName to return the \"NORTH\" literal; got: \(stringLiterals)")
            }
        }
    }
}
#endif
