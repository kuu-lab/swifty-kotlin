#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct BoxingIntegrationTests {
    @Test func testBoxingIntegration() throws {
        let sources = [
            """
            package boxing.sample0

            fun pairTripleBoxing() {
                val p = Pair(1, "one")
                val t = Triple(2, 3, "three")
                val p2 = 4 to "four"
            }
            """,
            """
            package boxing.sample1

            fun mutableListAdd(list: MutableList<Int>) {
                list.add(1)
            }
            """,
            """
            package boxing.sample2

            fun untilInfix(): Boolean {
                return 10L in 10L until 20L
            }
            """,
            """
            package boxing.sample3

            fun arrayOfBoxes() {
                val arr = arrayOf(1, 2, 3)
            }
            """,
            """
            package boxing.sample4

            fun intArrayOfValues() {
                val arr = intArrayOf(1, 2, 3)
            }
            """,
            """
            package boxing.sample5

            fun arrayOfIndexedRead(): Double {
                val arr = arrayOf(1.5, 2.5)
                return arr[0]
            }
            """,
            """
            package boxing.sample6

            fun arrayOfIndexedAssign() {
                val arr = arrayOf(1.5, 2.5)
                arr[0] = 9.5
            }
            """,
            """
            package boxing.sample7

            fun intArrayOfIndexedAssign() {
                val arr = intArrayOf(1, 2)
                arr[0] = 9
            }
            """,
            """
            package boxing.sample8

            fun arrayOfSpread() {
                val other = arrayOf(10, 20)
                val arr = arrayOf(1, *other, 3)
            }
            """,
            """
            package boxing.sample9

            fun compoundAssignLong() {
                val arr = arrayOf(1L, 2L, 3L)
                arr[0] += 5L
            }
            """,
            """
            package boxing.sample10

            fun compoundAssignFloatingPoint() {
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
            package boxing.sample11

            fun genericArrayAssign(a: Array<*>) {
                val b = a as Array<Any?>
                b[0] = 42
            }
            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            // Use .object so bundled stdlib source bodies are lowered once and are
            // available for inlining in every fixture in this shared context.
            let ctx = makeCompilationContext(inputs: paths, emit: .object)
            try runToLowering(ctx)

            for path in paths {
                let errors = diagnosticsForPath(path, in: ctx).filter { $0.severity == .error }
                #expect(errors.isEmpty, "Shared boxing fixture should have no errors for \(path): \(errors.map(\.message))")
            }

            let module: KIRModule = try #require(ctx.kir)
            let interner = ctx.interner

            do {
                let function = try findKIRFunction(named: "pairTripleBoxing", in: module, interner: interner)
                let boxingCalls = function.body.filter { instruction in
                    if case let .call(_, callee, _, _, _, _, _, _) = instruction {
                        return interner.resolve(callee) == "kk_box_int"
                    }
                    return false
                }
                #expect(boxingCalls.count >= 4, "Should have boxed primitive arguments for Pair and Triple. Found \(boxingCalls.count)")
            }

            do {
                let function = try findKIRFunction(named: "mutableListAdd", in: module, interner: interner)
                let boxingCalls = function.body.filter { instruction in
                    if case let .call(_, callee, _, _, _, _, _, _) = instruction {
                        return interner.resolve(callee) == "kk_box_int"
                    }
                    return false
                }
                #expect(boxingCalls.count == 1, "MutableList.add should box its primitive argument. Found \(boxingCalls.count)")
            }

            do {
                var rangeResults: Set<KIRExprID> = []
                for loweredFunction in findAllKIRFunctions(in: module) {
                    for instruction in loweredFunction.body {
                        if case let .call(_, callee, _, result, _, _, _, _) = instruction,
                           interner.resolve(callee) == "__kk_op_rangeUntil",
                           let result
                        {
                            rangeResults.insert(result)
                        }
                    }
                }
                #expect(!rangeResults.isEmpty, "Expected a __kk_op_rangeUntil call in the lowered module")

                let erroneousUnboxCalls = findAllKIRFunctions(in: module).flatMap { loweredFunction in
                    loweredFunction.body.filter { instruction in
                        if case let .call(_, callee, arguments, _, _, _, _, _) = instruction {
                            let calleeName = interner.resolve(callee)
                            return (calleeName == "kk_unbox_long" || calleeName == "kk_unbox_int")
                                && arguments.contains { rangeResults.contains($0) }
                        }
                        return false
                    }
                }
                #expect(
                    erroneousUnboxCalls.isEmpty,
                    "__kk_op_rangeUntil's boxed range result must not be unboxed. Found \(erroneousUnboxCalls.count) offending call(s)"
                )
            }

            do {
                let function = try findKIRFunction(named: "arrayOfBoxes", in: module, interner: interner)
                let boxingCalls = function.body.filter { instruction in
                    if case let .call(_, callee, _, _, _, _, _, _) = instruction {
                        return interner.resolve(callee) == "kk_box_int"
                    }
                    return false
                }
                #expect(boxingCalls.count == 3, "arrayOf(...) should box every primitive element. Found \(boxingCalls.count)")
            }

            do {
                let function = try findKIRFunction(named: "intArrayOfValues", in: module, interner: interner)
                let boxingCalls = function.body.filter { instruction in
                    if case let .call(_, callee, _, _, _, _, _, _) = instruction {
                        return interner.resolve(callee) == "kk_box_int"
                    }
                    return false
                }
                #expect(boxingCalls.isEmpty, "intArrayOf(...) must not box its elements. Found \(boxingCalls.count)")
            }

            do {
                let function = try findKIRFunction(named: "arrayOfIndexedRead", in: module, interner: interner)
                let boxCalls = function.body.filter { instruction in
                    if case let .call(_, callee, _, _, _, _, _, _) = instruction {
                        return interner.resolve(callee) == "kk_box_double_nonnull"
                    }
                    return false
                }
                let unboxCalls = function.body.filter { instruction in
                    if case let .call(_, callee, _, _, _, _, _, _) = instruction {
                        return interner.resolve(callee) == "kk_unbox_double"
                    }
                    return false
                }
                #expect(!boxCalls.isEmpty, "Constructing arrayOf(1.5, 2.5) should box its elements. Found \(boxCalls.count)")
                #expect(!unboxCalls.isEmpty, "arr[0] on Array<Double> should unbox the read element. Found \(unboxCalls.count)")
            }

            do {
                let function = try findKIRFunction(named: "arrayOfIndexedAssign", in: module, interner: interner)
                let boxingCalls = function.body.filter { instruction in
                    if case let .call(_, callee, _, _, _, _, _, _) = instruction {
                        return interner.resolve(callee) == "kk_box_double_nonnull"
                    }
                    return false
                }
                #expect(boxingCalls.count == 3, "arr[0] = 9.5 on Array<Double> should box the assigned value. Found \(boxingCalls.count)")
            }

            do {
                let function = try findKIRFunction(named: "intArrayOfIndexedAssign", in: module, interner: interner)
                let boxingCalls = function.body.filter { instruction in
                    if case let .call(_, callee, _, _, _, _, _, _) = instruction {
                        return interner.resolve(callee) == "kk_box_int"
                    }
                    return false
                }
                #expect(boxingCalls.isEmpty, "arr[0] = 9 on an IntArray must not box the assigned value. Found \(boxingCalls.count)")
            }

            do {
                let function = try findKIRFunction(named: "arrayOfSpread", in: module, interner: interner)
                let boxingCalls = function.body.filter { instruction in
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
                let function = try findKIRFunction(named: "compoundAssignLong", in: module, interner: interner)
                let boxLongNonnullCalls = function.body.filter { instruction in
                    if case let .call(_, callee, _, _, _, _, _, _) = instruction {
                        return interner.resolve(callee) == "kk_box_long_nonnull"
                    }
                    return false
                }
                let unboxLongCalls = function.body.filter { instruction in
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
                let function = try findKIRFunction(named: "compoundAssignFloatingPoint", in: module, interner: interner)
                let callees = function.body.compactMap { instruction -> String? in
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
                let function = try findKIRFunction(named: "genericArrayAssign", in: module, interner: interner)
                let callees = function.body.compactMap { instruction -> String? in
                    guard case let .call(_, callee, _, _, _, _, _, _) = instruction else {
                        return nil
                    }
                    return interner.resolve(callee)
                }
                #expect(!callees.contains("kk_op_cast"))
                #expect(callees.contains("kk_box_int"))
                #expect(callees.contains("kk_array_set"))
            }
        }
    }
}
#endif
