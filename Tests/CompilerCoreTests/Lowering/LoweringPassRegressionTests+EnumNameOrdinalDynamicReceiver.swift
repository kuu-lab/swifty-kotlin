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
    func testEnumNameOnFunctionParameterLowersToHelperCallWithReceiver() throws {
        let source = """
        enum class Direction { NORTH, SOUTH }
        fun printName(d: Direction) {
            println(d.name)
        }
        fun main() {
            printName(Direction.NORTH)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "EnumNameDynamicParam", emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            #expect(!ctx.diagnostics.hasError)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "printName", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)

            #expect(!callees.contains("name"),
                    "the raw unresolved \"name\" call must be rewritten away; callees: \(callees)")
            #expect(callees.contains(where: { $0.hasPrefix("$enumOrdinalToName$") }),
                    "expected a rewrite to $enumOrdinalToName$<id>; callees: \(callees)")

            let helperCalls = body.compactMap { instruction -> Int? in
                guard case let .call(_, callee, arguments, _, _, _, _, _) = instruction,
                      ctx.interner.resolve(callee).hasPrefix("$enumOrdinalToName$")
                else { return nil }
                return arguments.count
            }
            #expect(helperCalls == [1], "the receiver must survive as the helper's sole argument; got: \(helperCalls)")
        }
    }

    @Test
    func testEnumOrdinalOnFunctionParameterLowersToUnboxCallWithReceiver() throws {
        let source = """
        enum class Direction { NORTH, SOUTH }
        fun printOrdinal(d: Direction) {
            println(d.ordinal)
        }
        fun main() {
            printOrdinal(Direction.SOUTH)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "EnumOrdinalDynamicParam", emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            #expect(!ctx.diagnostics.hasError)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "printOrdinal", in: module, interner: ctx.interner)
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
    }

    @Test
    func testEnumNameOnCollectionHOFLambdaParameterLowersToHelperCall() throws {
        // The originally reported shape: a lambda parameter of enum type
        // passed to a stdlib collection HOF (forEach), not a direct function
        // parameter.
        let source = """
        enum class Direction { NORTH, SOUTH }
        fun main() {
            listOf(Direction.NORTH, Direction.SOUTH).forEach { d -> println(d.name) }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "EnumNameHOFLambdaParam", emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            #expect(!ctx.diagnostics.hasError)

            let module = try #require(ctx.kir)
            let allCallees = findAllKIRFunctions(in: module).flatMap { function in
                extractCallees(from: function.body, interner: ctx.interner)
            }

            #expect(!allCallees.contains("name"),
                    "the raw unresolved \"name\" call must be rewritten away; callees: \(allCallees)")
            #expect(allCallees.contains(where: { $0.hasPrefix("$enumOrdinalToName$") }),
                    "expected a rewrite to $enumOrdinalToName$<id>; callees: \(allCallees)")
        }
    }

    @Test
    func testEnumNameOnLiteralEntryReceiverStaysOnFastPath() throws {
        // Regression guard: a literal entry reference (tryLowerEnumEntryPropertyRead)
        // resolves straight to the per-entry NORTH$enumName() helper and must keep
        // bypassing the generic $enumOrdinalToName(receiver) rewrite entirely -- no
        // behavior change for the already-working path.
        let source = """
        enum class Direction { NORTH, SOUTH }
        fun main() {
            println(Direction.NORTH.name)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "EnumNameLiteralConstFold", emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            #expect(!ctx.diagnostics.hasError)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)

            #expect(!callees.contains(where: { $0.hasPrefix("$enumOrdinalToName$") }),
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
#endif
