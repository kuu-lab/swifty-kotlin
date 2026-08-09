#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension BuildKIRRegressionTests {
    @Test func testVarargAndLocalFunctionsKIR() throws {
        let sources = [
            """
            package sample0
            fun tagged0(tag: String, vararg values: Int): Int = 0
            fun main0() = tagged0(tag = "x", 1, 2)
            """,
            """
            package sample2
            fun format2(prefix: String = ">>", vararg nums: Int, suffix: String = "<<"): Int = 0
            fun main2() = format2(prefix = "!", 10, 20, 30)
            """,
            """
            package sample3
            class Acc3 {
                fun add3(vararg vals: Int): Int = 0
            }
            fun main3(a: Acc3) = a.add3(1, 2, 3)
            """,
            """
            package sample5
            fun log5(level: Int = 0, vararg msgs: Int): Int = 0
            fun main5() {
                log5(1, 2, 3)
                log5(level = 5, 10, 20)
                log5()
            }
            """,
            """
            package sample6
            fun report6(label: String, vararg values: Int): Int = 0
            fun main6() = report6(label = "test", 10, 20, 30)
            """,
            """
            package sample7
            fun bar7(vararg cs: Char): Int = 0
            fun main7() = bar7('a', 'b', 'c')
            """,
            """
            package sample8
            fun flag8(vararg bs: Boolean): Int = 0
            fun main8() = flag8(true, false, true)
            """,
            """
            package sample9
            fun nums9(vararg ds: Double): Int = 0
            fun main9() = nums9(1.5, 2.5, 3.5)
            """,
            """
            package sample10
            fun nums10(vararg ls: Long): Int = 0
            fun main10() = nums10(1L, 2L, 3L)
            """,
            """
            package sample11
            fun doubleArrayFactory11() = doubleArrayOf(1.5, 2.5)
            fun genericArrayFactory11() = arrayOf(1.5, 2.5)
            """,
            """
            package sample12
            fun localHelperMain12(): Int {
                fun helper(x: Int): Int = x * 2
                return helper(21)
            }
            """,
            """
            package sample13
            fun localAddMain13(): Int {
                fun add(a: Int, b: Int): Int = a + b
                return add(1, 2)
            }
            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths, emit: .kirDump)
            try runToKIR(ctx)
            #expect(!ctx.diagnostics.hasError, "Expected vararg and local function cases to compile without errors.")

            let module = try #require(ctx.kir)
            let interner = ctx.interner

            do {
                let body = try findKIRFunctionBody(named: "main0", in: module, interner: interner)
                let callNames = extractCallees(from: body, interner: interner)
                #expect(callNames.contains("kk_array_new"))
                #expect(callNames.contains("kk_array_set"))
            }

            do {
                let body = try findKIRFunctionBody(named: "main2", in: module, interner: interner)
                let callNames = extractCallees(from: body, interner: interner)
                #expect(callNames.contains("kk_array_new"))
            }

            do {
                let body = try findKIRFunctionBody(named: "main3", in: module, interner: interner)
                let callNames = extractCallees(from: body, interner: interner)
                #expect(callNames.contains("kk_array_new"))
                #expect(callNames.contains("kk_array_set"))
            }

            do {
                let body = try findKIRFunctionBody(named: "main5", in: module, interner: interner)
                let callNames = extractCallees(from: body, interner: interner)
                #expect(callNames.filter { $0 == "kk_array_new" }.count >= 2)
            }

            do {
                let body = try findKIRFunctionBody(named: "main6", in: module, interner: interner)
                let callNames = extractCallees(from: body, interner: interner)
                #expect(callNames.contains("kk_array_new"))
                #expect(callNames.contains("kk_array_set"))
            }

            do {
                let body = try findKIRFunctionBody(named: "main7", in: module, interner: interner)
                let callNames = extractCallees(from: body, interner: interner)
                #expect(callNames.filter { $0 == "kk_box_char" }.count == 3)
            }

            do {
                let body = try findKIRFunctionBody(named: "main8", in: module, interner: interner)
                let callNames = extractCallees(from: body, interner: interner)
                #expect(callNames.filter { $0 == "kk_box_bool" }.count == 3)
            }

            do {
                let body = try findKIRFunctionBody(named: "main9", in: module, interner: interner)
                let callNames = extractCallees(from: body, interner: interner)
                #expect(callNames.filter { $0 == "kk_box_double" }.count == 3)
            }

            do {
                let body = try findKIRFunctionBody(named: "main10", in: module, interner: interner)
                let callNames = extractCallees(from: body, interner: interner)
                #expect(callNames.filter { $0 == "kk_box_long_nonnull" }.count == 3)
            }

            do {
                let doubleArrayCalls = extractCallees(
                    from: try findKIRFunctionBody(named: "doubleArrayFactory11", in: module, interner: interner),
                    interner: interner
                )
                let genericArrayCalls = extractCallees(
                    from: try findKIRFunctionBody(named: "genericArrayFactory11", in: module, interner: interner),
                    interner: interner
                )
                #expect(!doubleArrayCalls.contains("kk_box_double"))
                #expect(genericArrayCalls.filter { $0 == "kk_box_double" }.count == 2)
            }

            #expect(module.functionCount >= 2, "Expected KIR to contain local functions")
        }
    }

    @Test func testVarargSpreadFlagIsParsedInCallArgument() throws {
        let source = """
        package sample1
        fun collect1(vararg items: Int): Int = 0
        fun spreadMain1() {
            val arr = IntArray(2)
            collect1(*arr)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try LoadSourcesPhase().run(ctx)
            try LexPhase().run(ctx)
            try ParsePhase().run(ctx)
            try BuildASTPhase().run(ctx)

            let ast = try #require(ctx.ast)
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

    @Test func testABILoweringSkipsBoxingForVarargPackedArrayArgument() throws {
        let source = """
        package sample4
        fun sum4(vararg items: Int): Int = 0
        fun abiMain4() = sum4(1, 2, 3)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "abiMain4", in: module, interner: ctx.interner)
            let callNames = extractCallees(from: body, interner: ctx.interner)

            let loweredAggregateCalls = body.filter { instruction in
                guard case let .call(_, callee, _, _, _, _, _, _) = instruction else { return false }
                let calleeName = ctx.interner.resolve(callee)
                return calleeName == "sum4" || calleeName == "kk_list_sum"
            }
            #expect(!loweredAggregateCalls.isEmpty)

            for call in loweredAggregateCalls {
                guard case let .call(_, _, arguments, _, _, _, _, _) = call else { continue }
                for arg in arguments {
                    guard let argKind = module.arena.expr(arg) else { continue }
                    if case .intLiteral = argKind {
                        Issue.record("Unexpected intLiteral as direct argument to sum4; expected a packed array reference.")
                    }
                }
            }

            let sumIndex = callNames.firstIndex(where: { $0 == "sum4" || $0 == "kk_list_sum" })
            let boxIntIndices = callNames.indices.filter { callNames[$0] == "kk_box_int" }
            if let sumIdx = sumIndex {
                let boxCallsAfterArrayPacking = boxIntIndices.filter { $0 > sumIdx }
                #expect(boxCallsAfterArrayPacking.isEmpty)
            }
        }
    }
}
#endif
