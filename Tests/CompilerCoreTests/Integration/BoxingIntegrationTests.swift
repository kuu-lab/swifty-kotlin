#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct BoxingIntegrationTests {
    @Test func testBoxingIntegration() throws {
        let sources = [
            """
            package sample0

            fun test0() {
                val p = Pair(1, "one")
                val t = Triple(2, 3, "three")
                val p2 = 4 to "four"
            }
            """,
            """
            package sample1

            fun test1(list: MutableList<Int>) {
                list.add(1)
            }
            """,
            """
            package sample2

            fun test2(): Boolean {
                return 10L in 10L until 20L
            }
            """,
            """
            package sample3

            fun test3() {
                val arr = arrayOf(1, 2, 3)
            }
            """,
            """
            package sample4

            fun test4() {
                val arr = intArrayOf(1, 2, 3)
            }
            """,
            """
            package sample5

            fun test5(): Double {
                val arr = arrayOf(1.5, 2.5)
                return arr[0]
            }
            """,
            """
            package sample6

            fun test6() {
                val arr = arrayOf(1.5, 2.5)
                arr[0] = 9.5
            }
            """,
            """
            package sample7

            fun test7() {
                val arr = intArrayOf(1, 2)
                arr[0] = 9
            }
            """,
            """
            package sample8

            fun test8() {
                val other = arrayOf(10, 20)
                val arr = arrayOf(1, *other, 3)
            }
            """,
            """
            package sample9

            fun test9() {
                val arr = arrayOf(1L, 2L, 3L)
                arr[0] += 5L
            }
            """,
            """
            package sample10

            fun test10() {
                val doubles = arrayOf(1.5, 2.5)
                doubles[0] += 0.5
                doubles[1] -= 0.5
                doubles[0] *= 2.0
                doubles[1] /= 2.0
                doubles[0] %= 0.75

                val floats = arrayOf(1.5f, 2.5f)
                floats[0] += 0.5f
                floats[1] -= 0.5f
                floats[0] *= 2.0f
                floats[1] /= 2.0f
                floats[0] %= 0.75f

                val primitiveDoubles = doubleArrayOf(1.5, 2.5)
                primitiveDoubles[0] += 0.5
                primitiveDoubles[1] -= 0.5
                primitiveDoubles[0] *= 2.0
                primitiveDoubles[1] /= 2.0
                primitiveDoubles[0] %= 0.75

                val primitiveFloats = floatArrayOf(1.5f, 2.5f)
                primitiveFloats[0] += 0.5f
                primitiveFloats[1] -= 0.5f
                primitiveFloats[0] *= 2.0f
                primitiveFloats[1] /= 2.0f
                primitiveFloats[0] %= 0.75f
            }
            """,
            """
            package sample11

            fun assign11(a: Array<*>) {
                val b = a as Array<Any?>
                b[0] = 42
            }
            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runToLowering(ctx)

            let module: KIRModule = try #require(ctx.kir)
            let interner = ctx.interner

            do {
                let testFunc = try findKIRFunction(named: "test0", in: module, interner: interner)
                let boxingCalls = testFunc.body.filter { instruction in
                    if case let .call(_, callee, _, _, _, _, _, _) = instruction {
                        return interner.resolve(callee) == "kk_box_int"
                    }
                    return false
                }
                #expect(boxingCalls.count >= 4, "Should have boxed primitive arguments for Pair and Triple. Found \(boxingCalls.count)")
            }

            do {
                let testFunc = try findKIRFunction(named: "test1", in: module, interner: interner)
                let boxingCalls = testFunc.body.filter { instruction in
                    if case let .call(_, callee, _, _, _, _, _, _) = instruction {
                        return interner.resolve(callee) == "kk_box_int"
                    }
                    return false
                }
                #expect(boxingCalls.count == 1, "MutableList.add should box its primitive argument. Found \(boxingCalls.count)")
            }

            do {
                let testFunc = try findKIRFunction(named: "test2", in: module, interner: interner)
                var rangeResults: Set<KIRExprID> = []
                for instruction in testFunc.body {
                    if case let .call(_, callee, _, result, _, _, _, _) = instruction,
                       interner.resolve(callee) == "kk_op_rangeUntil",
                       let result
                    {
                        rangeResults.insert(result)
                    }
                }
                #expect(!rangeResults.isEmpty, "Expected a kk_op_rangeUntil call in the lowered body")

                let erroneousUnboxCalls = testFunc.body.filter { instruction in
                    if case let .call(_, callee, arguments, _, _, _, _, _) = instruction {
                        let calleeName = interner.resolve(callee)
                        return (calleeName == "kk_unbox_long" || calleeName == "kk_unbox_int")
                            && arguments.contains { rangeResults.contains($0) }
                    }
                    return false
                }
                #expect(
                    erroneousUnboxCalls.isEmpty,
                    "kk_op_rangeUntil's boxed range result must not be unboxed. Found \(erroneousUnboxCalls.count) offending call(s)"
                )
            }

            do {
                let testFunc = try findKIRFunction(named: "test3", in: module, interner: interner)
                let boxingCalls = testFunc.body.filter { instruction in
                    if case let .call(_, callee, _, _, _, _, _, _) = instruction {
                        return interner.resolve(callee) == "kk_box_int"
                    }
                    return false
                }
                #expect(boxingCalls.count == 3, "arrayOf(...) should box every primitive element. Found \(boxingCalls.count)")
            }

            do {
                let testFunc = try findKIRFunction(named: "test4", in: module, interner: interner)
                let boxingCalls = testFunc.body.filter { instruction in
                    if case let .call(_, callee, _, _, _, _, _, _) = instruction {
                        return interner.resolve(callee) == "kk_box_int"
                    }
                    return false
                }
                #expect(boxingCalls.isEmpty, "intArrayOf(...) must not box its elements. Found \(boxingCalls.count)")
            }

            do {
                let testFunc = try findKIRFunction(named: "test5", in: module, interner: interner)
                let boxCalls = testFunc.body.filter { instruction in
                    if case let .call(_, callee, _, _, _, _, _, _) = instruction {
                        return interner.resolve(callee) == "kk_box_double"
                    }
                    return false
                }
                let unboxCalls = testFunc.body.filter { instruction in
                    if case let .call(_, callee, _, _, _, _, _, _) = instruction {
                        return interner.resolve(callee) == "kk_unbox_double"
                    }
                    return false
                }
                #expect(!boxCalls.isEmpty, "Constructing arrayOf(1.5, 2.5) should box its elements. Found \(boxCalls.count)")
                #expect(!unboxCalls.isEmpty, "arr[0] on Array<Double> should unbox the read element. Found \(unboxCalls.count)")
            }

            do {
                let testFunc = try findKIRFunction(named: "test6", in: module, interner: interner)
                let boxingCalls = testFunc.body.filter { instruction in
                    if case let .call(_, callee, _, _, _, _, _, _) = instruction {
                        return interner.resolve(callee) == "kk_box_double"
                    }
                    return false
                }
                #expect(boxingCalls.count == 3, "arr[0] = 9.5 on Array<Double> should box the assigned value. Found \(boxingCalls.count)")
            }

            do {
                let testFunc = try findKIRFunction(named: "test7", in: module, interner: interner)
                let boxingCalls = testFunc.body.filter { instruction in
                    if case let .call(_, callee, _, _, _, _, _, _) = instruction {
                        return interner.resolve(callee) == "kk_box_int"
                    }
                    return false
                }
                #expect(boxingCalls.isEmpty, "arr[0] = 9 on an IntArray must not box the assigned value. Found \(boxingCalls.count)")
            }

            do {
                let testFunc = try findKIRFunction(named: "test8", in: module, interner: interner)
                let boxingCalls = testFunc.body.filter { instruction in
                    if case let .call(_, callee, _, _, _, _, _, _) = instruction {
                        return interner.resolve(callee) == "kk_box_int"
                    }
                    return false
                }
                #expect(
                    boxingCalls.count == 4,
                    "arrayOf(1, *other, 3) should box only its two non-spread literals (plus 2 for `other`). Found \(boxingCalls.count)"
                )
            }

            do {
                let testFunc = try findKIRFunction(named: "test9", in: module, interner: interner)
                let boxLongNonnullCalls = testFunc.body.filter { instruction in
                    if case let .call(_, callee, _, _, _, _, _, _) = instruction {
                        return interner.resolve(callee) == "kk_box_long_nonnull"
                    }
                    return false
                }
                let unboxLongCalls = testFunc.body.filter { instruction in
                    if case let .call(_, callee, _, _, _, _, _, _) = instruction {
                        return interner.resolve(callee) == "kk_unbox_long"
                    }
                    return false
                }
                #expect(
                    boxLongNonnullCalls.count == 4,
                    "arr[0] += 5L on Array<Long> should box array construction and the stored result as non-null Long. Found \(boxLongNonnullCalls.count)"
                )
                #expect(!unboxLongCalls.isEmpty, "arr[0] += 5L on Array<Long> should unbox the read element as Long. Found \(unboxLongCalls.count)")
            }

            do {
                let testFunc = try findKIRFunction(named: "test10", in: module, interner: interner)
                let callees = testFunc.body.compactMap { instruction -> String? in
                    guard case let .call(_, callee, _, _, _, _, _, _) = instruction else {
                        return nil
                    }
                    return interner.resolve(callee)
                }
                #expect(callees.filter { $0 == "kk_op_dadd" }.count == 2)
                #expect(callees.filter { $0 == "kk_op_dsub" }.count == 2)
                #expect(callees.filter { $0 == "kk_op_dmul" }.count == 2)
                #expect(callees.filter { $0 == "kk_op_ddiv" }.count == 2)
                #expect(callees.filter { $0 == "kk_op_dmod" }.count == 2)
                #expect(callees.filter { $0 == "kk_op_fadd" }.count == 2)
                #expect(callees.filter { $0 == "kk_op_fsub" }.count == 2)
                #expect(callees.filter { $0 == "kk_op_fmul" }.count == 2)
                #expect(callees.filter { $0 == "kk_op_fdiv" }.count == 2)
                #expect(callees.filter { $0 == "kk_op_fmod" }.count == 2)
                #expect(callees.filter { $0 == "kk_op_add" }.isEmpty)
                #expect(callees.filter { $0 == "kk_op_sub" }.isEmpty)
                #expect(callees.filter { $0 == "kk_op_mul" }.isEmpty)
                #expect(callees.filter { $0 == "kk_op_div" }.isEmpty)
                #expect(callees.filter { $0 == "kk_op_mod" }.isEmpty)
            }

            do {
                let assignFunc = try findKIRFunction(named: "assign11", in: module, interner: interner)
                let callees = assignFunc.body.compactMap { instruction -> String? in
                    guard case let .call(_, callee, _, _, _, _, _, _) = instruction else {
                        return nil
                    }
                    return interner.resolve(callee)
                }
                #expect(callees.contains("kk_op_cast") == false)
                #expect(callees.contains("kk_box_int"))
                #expect(callees.contains("kk_array_set"))
            }
        }
    }
}
#endif
