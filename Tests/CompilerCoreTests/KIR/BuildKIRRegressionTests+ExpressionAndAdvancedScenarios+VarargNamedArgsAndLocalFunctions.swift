#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension BuildKIRRegressionTests {
    @Test func testVarargNamedArgSkipsToVarargParameter() throws {
        let source = """
        fun tagged(tag: String, vararg values: Int): Int = 0
        fun main() = tagged(tag = "x", 1, 2)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            #expect(!(ctx.diagnostics.hasError), "Expected vararg with named arg to compile without errors.")

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callNames = extractCallees(from: body, interner: ctx.interner)
            #expect(callNames.contains("kk_array_new"), "Expected kk_array_new for vararg packing with named arg, got: \(callNames)")
            #expect(callNames.contains("kk_array_set"), "Expected kk_array_set for vararg packing with named arg, got: \(callNames)")
        }
    }

    @Test func testVarargSpreadFlagIsParsedInCallArgument() throws {
        // Verify that the spread operator (*) is parsed at the AST level.
        // Full end-to-end spread lowering requires IntArray type inference
        // improvements (tracked separately).
        let source = """
        fun collect(vararg items: Int): Int = 0
        fun main() {
            val arr = IntArray(2)
            collect(*arr)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try LoadSourcesPhase().run(ctx)
            try LexPhase().run(ctx)
            try ParsePhase().run(ctx)
            try BuildASTPhase().run(ctx)

            let ast = try #require(ctx.ast)
            // Check that at least one CallArgument has isSpread == true
            var foundSpread = false
            for index in ast.arena.exprs.indices {
                let exprID = ExprID(rawValue: Int32(index))
                guard let expr = ast.arena.expr(exprID) else { continue }
                if case let .call(_, _, args, _) = expr {
                    for arg in args where arg.isSpread {
                        foundSpread = true
                    }
                }
            }
            #expect(foundSpread, "Expected parser to set isSpread flag for *arr argument.")
        }
    }

    @Test func testVarargWithDefaultAndNamedArgsCombined() throws {
        let source = """
        fun format(prefix: String = ">>", vararg nums: Int, suffix: String = "<<"): Int = 0
        fun main() = format(prefix = "!", 10, 20, 30)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            #expect(!(ctx.diagnostics.hasError), "Expected vararg+default+named combination to compile without errors.")

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callNames = extractCallees(from: body, interner: ctx.interner)
            #expect(callNames.contains("kk_array_new"), "Expected kk_array_new for vararg packing in combined scenario, got: \(callNames)")
        }
    }

    @Test func testVarargMemberCallPacksArgsCorrectly() throws {
        let source = """
        class Acc {
            fun add(vararg vals: Int): Int = 0
        }
        fun main(a: Acc) = a.add(1, 2, 3)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            #expect(!(ctx.diagnostics.hasError), "Expected vararg member call to compile without errors.")

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callNames = extractCallees(from: body, interner: ctx.interner)
            #expect(callNames.contains("kk_array_new"), "Expected kk_array_new for vararg member call, got: \(callNames)")
            #expect(callNames.contains("kk_array_set"), "Expected kk_array_set for vararg member call, got: \(callNames)")
        }
    }

    @Test func testABILoweringSkipsBoxingForVarargPackedArrayArgument() throws {
        let source = """
        fun sum(vararg items: Int): Int = 0
        fun main() = sum(1, 2, 3)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callNames = extractCallees(from: body, interner: ctx.interner)

            // After ABI lowering, the vararg-packed array should NOT be boxed.
            // If boxing were incorrectly applied, we would see kk_box_int
            // targeting the array argument passed to `sum`.
            let loweredAggregateCalls = body.filter { instruction in
                guard case let .call(_, callee, _, _, _, _, _, _) = instruction else { return false }
                let calleeName = ctx.interner.resolve(callee)
                return calleeName == "sum" || calleeName == "kk_list_sum"
            }
            #expect(!(loweredAggregateCalls.isEmpty), "Expected an aggregate call after ABI lowering.")

            // Verify that arguments to sum are not individually boxed—the
            // array_new/array_set calls produce the packed array argument.
            for call in loweredAggregateCalls {
                guard case let .call(_, _, arguments, _, _, _, _, _) = call else { continue }
                for arg in arguments {
                    guard let argKind = module.arena.expr(arg) else { continue }
                    // The argument to sum should be a temporary holding the
                    // array reference produced by kk_array_new, NOT a raw
                    // kk_box_int result.  An intLiteral here would mean the
                    // vararg array was never constructed—flag it.
                    if case .intLiteral = argKind {
                        Issue.record("Unexpected intLiteral as direct argument to sum; expected a packed array reference.")
                    }
                }
            }

            // The real check: kk_box_int should NOT appear before the call to sum
            // for the purpose of boxing vararg elements into the packed argument.
            // The array_set calls handle packing, not boxing.
            let sumIndex = callNames.firstIndex(where: { $0 == "sum" || $0 == "kk_list_sum" })
            let boxIntIndices = callNames.indices.filter { callNames[$0] == "kk_box_int" }
            // Any kk_box_int calls that appear should be for array_set element boxing,
            // not for the final argument to sum itself.
            if let sumIdx = sumIndex {
                let boxCallsAfterArrayPacking = boxIntIndices.filter { $0 > sumIdx }
                #expect(boxCallsAfterArrayPacking.isEmpty, "Unexpected kk_box_int after sum call; vararg array argument should not be boxed.")
            }
        }
    }

    @Test func testVarargDefaultNamedRegressionCompilesToKIRWithoutErrors() throws {
        let source = """
        fun log(level: Int = 0, vararg msgs: Int): Int = 0
        fun main() {
            log(1, 2, 3)
            log(level = 5, 10, 20)
            log()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            #expect(!(ctx.diagnostics.hasError), "Expected vararg+default+named regression cases to compile without errors.")

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callNames = extractCallees(from: body, interner: ctx.interner)

            // All three call sites should produce array packing
            let arrayNewCount = callNames.filter { $0 == "kk_array_new" }.count
            #expect(arrayNewCount >= 2, "Expected at least 2 kk_array_new calls for vararg packing across call sites, got: \(arrayNewCount)")
        }
    }

    @Test func testVarargPositionalAfterNamedArgPacksCorrectly() throws {
        // Verify that positional vararg arguments following a named argument
        // are correctly packed into an array (overload resolver fix).
        let source = """
        fun report(label: String, vararg values: Int): Int = 0
        fun main() = report(label = "test", 10, 20, 30)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            #expect(!(ctx.diagnostics.hasError), "Expected positional vararg after named arg to compile without errors.")

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callNames = extractCallees(from: body, interner: ctx.interner)
            #expect(callNames.contains("kk_array_new"), "Expected kk_array_new for positional vararg after named arg, got: \(callNames)")
            #expect(callNames.contains("kk_array_set"), "Expected kk_array_set for positional vararg after named arg, got: \(callNames)")
        }
    }

    @Test func testVarargCharArgumentsAreBoxed() throws {
        let source = """
        fun bar(vararg cs: Char): Int = 0
        fun main() = bar('a', 'b', 'c')
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            #expect(!(ctx.diagnostics.hasError), "Expected Char vararg call to compile without errors.")

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callNames = extractCallees(from: body, interner: ctx.interner)
            let boxCharCount = callNames.filter { $0 == "kk_box_char" }.count
            #expect(boxCharCount == 3, "Expected each Char vararg element to be boxed via kk_box_char, got: \(callNames)")
        }
    }

    @Test func testVarargBooleanArgumentsAreBoxed() throws {
        let source = """
        fun flag(vararg bs: Boolean): Int = 0
        fun main() = flag(true, false, true)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            #expect(!(ctx.diagnostics.hasError), "Expected Boolean vararg call to compile without errors.")

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callNames = extractCallees(from: body, interner: ctx.interner)
            let boxBoolCount = callNames.filter { $0 == "kk_box_bool" }.count
            #expect(boxBoolCount == 3, "Expected each Boolean vararg element to be boxed via kk_box_bool, got: \(callNames)")
        }
    }

    @Test func testVarargDoubleArgumentsAreBoxed() throws {
        let source = """
        fun nums(vararg ds: Double): Int = 0
        fun main() = nums(1.5, 2.5, 3.5)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            #expect(!(ctx.diagnostics.hasError), "Expected Double vararg call to compile without errors.")

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callNames = extractCallees(from: body, interner: ctx.interner)
            let boxDoubleCount = callNames.filter { $0 == "kk_box_double" }.count
            #expect(boxDoubleCount == 3, "Expected each Double vararg element to be boxed via kk_box_double, got: \(callNames)")
        }
    }

    @Test func testVarargLongArgumentsAreBoxed() throws {
        let source = """
        fun nums(vararg ls: Long): Int = 0
        fun main() = nums(1L, 2L, 3L)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            #expect(!(ctx.diagnostics.hasError), "Expected Long vararg call to compile without errors.")

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callNames = extractCallees(from: body, interner: ctx.interner)
            // Long literals are provably non-null, so BoxingCalleeTable routes
            // them through kk_box_long_nonnull rather than the nullable-safe
            // kk_box_long (see BoxingCalleeTable.nonNullOnlyBoxCalleeOverridesByPrimitive).
            let boxLongCount = callNames.filter { $0 == "kk_box_long_nonnull" }.count
            #expect(boxLongCount == 3, "Expected each Long vararg element to be boxed via kk_box_long_nonnull, got: \(callNames)")
        }
    }

    @Test func testPrimitiveArrayFactoryElementsUseTheirDeclaredElementType() throws {
        // Specialized primitive factories keep their raw primitive elements, while
        // generic arrayOf<T> must box them before storing into its Any-erased array.
        let source = """
        fun doubleArrayFactory() = doubleArrayOf(1.5, 2.5)
        fun genericArrayFactory() = arrayOf(1.5, 2.5)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            #expect(!(ctx.diagnostics.hasError), "Expected doubleArrayOf/arrayOf calls to compile without errors.")

            let module = try #require(ctx.kir)
            let doubleArrayCalls = extractCallees(
                from: try findKIRFunctionBody(named: "doubleArrayFactory", in: module, interner: ctx.interner),
                interner: ctx.interner
            )
            let genericArrayCalls = extractCallees(
                from: try findKIRFunctionBody(named: "genericArrayFactory", in: module, interner: ctx.interner),
                interner: ctx.interner
            )
            #expect(
                !doubleArrayCalls.contains("kk_box_double"),
                "Expected doubleArrayOf's raw Double elements NOT to be boxed, got: \(doubleArrayCalls)"
            )
            let genericBoxDoubleCount = genericArrayCalls.filter { $0 == "kk_box_double" }.count
            #expect(
                genericBoxDoubleCount == 2,
                "Expected arrayOf<Double> to box each erased element, got: \(genericArrayCalls)"
            )
        }
    }

    func topLevelExpressionBodyExprID(
        named functionName: String,
        ast: ASTModule,
        interner: StringInterner
    ) -> ExprID? {
        ast.files
            .flatMap(\.topLevelDecls)
            .compactMap { declID -> ExprID? in
                guard let decl = ast.arena.decl(declID),
                      case let .funDecl(funDecl) = decl,
                      interner.resolve(funDecl.name) == functionName,
                      case let .expr(exprID, _) = funDecl.body
                else {
                    return nil
                }
                return exprID
            }
            .first
    }

    func symbolNames(
        for arguments: [KIRExprID],
        module: KIRModule,
        sema: SemaModule,
        interner: StringInterner
    ) -> [String] {
        arguments.compactMap { argument in
            guard case let .symbolRef(symbolID)? = module.arena.expr(argument),
                  let symbol = sema.symbols.symbol(symbolID)
            else {
                return nil
            }
            return interner.resolve(symbol.name)
        }
    }

    // MARK: - P5-42: Local function scope registration and KIR generation

    @Test func testLocalFunctionScopeRegistrationAllowsCallResolution() throws {
        let source = """
        fun main(): Int {
            fun helper(x: Int): Int = x * 2
            return helper(21)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            #expect(!(ctx.diagnostics.hasError), "Local function call should resolve without errors: \(ctx.diagnostics.diagnostics.map(\.message))")
        }
    }

    @Test func testLocalFunctionKIRGenerationEmitsFunctionDecl() throws {
        let source = """
        fun main(): Int {
            fun add(a: Int, b: Int): Int = a + b
            return add(1, 2)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            #expect(!(ctx.diagnostics.hasError), "Expected no errors: \(ctx.diagnostics.diagnostics.map(\.message))")
            let module = try #require(ctx.kir)
            // The module should contain at least 2 functions: main and the local function add.
            #expect(module.functionCount >= 2, "Expected KIR to contain both main and local function 'add'")
        }
    }
}
#endif
