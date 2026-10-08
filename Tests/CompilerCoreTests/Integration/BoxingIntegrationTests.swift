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
            let sema = try #require(ctx.sema)
            let boxing = BoxingCalleeTable(interner: interner)
            let intBox = try #require(boxing.boxCallee(for: .int))
            let staticIntBox = try #require(boxing.boxCallee(
                for: .primitive(.int, .nonNull), requireNonNull: true, preferStaticPrimitive: true
            ))
            let doubleBox = try #require(boxing.boxCallee(for: .primitive(.double, .nonNull), requireNonNull: true))
            // Direct indexed reads and erased ABI returns use different carriers.
            let doubleUnboxCallees = try [false, true].map { preferStaticPrimitive in
                try #require(boxing.unboxCallee(
                    for: .primitive(.double, .nonNull), requireNonNull: true,
                    preferStaticPrimitive: preferStaticPrimitive
                ))
            }
            let longBox = try #require(boxing.boxCallee(for: .primitive(.long, .nonNull), requireNonNull: true))
            let longUnbox = try #require(boxing.unboxCallee(for: .long))
            let intUnbox = try #require(boxing.unboxCallee(for: .int))
            let rangeNames = RangeLookupNames(interner: interner)
            let arrayNames = ArrayLookupNames(interner: interner)

            // One scan of the lowered module, shared by every fixture below.
            let allFunctions = findAllKIRFunctions(in: module)
            let functionsByName = Dictionary(
                allFunctions.map { ($0.name, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            func calleeIDs(in body: [KIRInstruction]) -> [InternedString] {
                body.compactMap { instruction in
                    guard case let .call(_, callee, _, _, _, _, _, _) = instruction else { return nil }
                    return callee
                }
            }
            /// Callee identities of every `.call` in the named lowered function, in body order.
            func calleeIDs(of functionName: String) throws -> [InternedString] {
                let function = try requireTestValue(
                    functionsByName[interner.intern(functionName)],
                    "KIR function '\(functionName)' not found in module"
                )
                return calleeIDs(in: function.body)
            }

            do {
                let callees = try calleeIDs(of: "pairTripleBoxing")
                let boxingCalls = callees.filter { $0 == staticIntBox }
                #expect(boxingCalls.count >= 4, "Should have boxed primitive arguments for Pair and Triple. Found \(boxingCalls.count)")
            }

            do {
                let callees = try calleeIDs(of: "mutableListAdd")
                let boxingCalls = callees.filter { $0 == staticIntBox }
                #expect(boxingCalls.count == 1, "MutableList.add should box its primitive argument. Found \(boxingCalls.count)")
            }

            do {
                var rangeResults: Set<KIRExprID> = []
                for loweredFunction in allFunctions {
                    for instruction in loweredFunction.body {
                        if case let .call(_, callee, _, result, _, _, _, _) = instruction,
                           callee == rangeNames.kkOpRangeUntilName,
                           let result
                        {
                            rangeResults.insert(result)
                        }
                    }
                }
                #expect(!rangeResults.isEmpty, "Expected a range-until factory call in the lowered module")

                let erroneousUnboxCalls = allFunctions.flatMap { loweredFunction in
                    loweredFunction.body.filter { instruction in
                        if case let .call(_, callee, arguments, _, _, _, _, _) = instruction {
                            return (callee == longUnbox || callee == intUnbox)
                                && arguments.contains { rangeResults.contains($0) }
                        }
                        return false
                    }
                }
                #expect(
                    erroneousUnboxCalls.isEmpty,
                    "The range factory's boxed result must not be unboxed. Found \(erroneousUnboxCalls.count) offending call(s)"
                )
            }

            do {
                let callees = try calleeIDs(of: "arrayOfBoxes")
                let boxingCalls = callees.filter { $0 == intBox }
                #expect(boxingCalls.count == 3, "arrayOf(...) should box every primitive element. Found \(boxingCalls.count)")
            }

            do {
                let callees = try calleeIDs(of: "intArrayOfValues")
                let boxingCalls = callees.filter { $0 == intBox }
                #expect(boxingCalls.isEmpty, "intArrayOf(...) must not box its elements. Found \(boxingCalls.count)")
            }

            do {
                let callees = try calleeIDs(of: "arrayOfIndexedRead")
                let boxCalls = callees.filter { $0 == doubleBox }
                let unboxCalls = callees.filter { doubleUnboxCallees.contains($0) }
                #expect(!boxCalls.isEmpty, "Constructing arrayOf(1.5, 2.5) should box its elements. Found \(boxCalls.count)")
                #expect(!unboxCalls.isEmpty, "arr[0] on Array<Double> should unbox the read element. Found \(unboxCalls.count); callees: \(callees.map(interner.resolve))")
            }

            do {
                let callees = try calleeIDs(of: "arrayOfIndexedAssign")
                let boxingCalls = callees.filter { $0 == doubleBox }
                #expect(boxingCalls.count == 3, "arr[0] = 9.5 on Array<Double> should box the assigned value. Found \(boxingCalls.count)")
            }

            do {
                let callees = try calleeIDs(of: "intArrayOfIndexedAssign")
                let boxingCalls = callees.filter { $0 == intBox }
                #expect(boxingCalls.isEmpty, "arr[0] = 9 on an IntArray must not box the assigned value. Found \(boxingCalls.count)")
            }

            do {
                let callees = try calleeIDs(of: "arrayOfSpread")
                let boxingCalls = callees.filter { $0 == intBox }
                #expect(
                    boxingCalls.count == 4,
                    "arrayOf(1, *other, 3) should box only its two non-spread literals (plus 2 for `other`). Found \(boxingCalls.count)"
                )
            }

            do {
                let callees = try calleeIDs(of: "compoundAssignLong")
                let boxLongNonnullCalls = callees.filter { $0 == longBox }
                let unboxLongCalls = callees.filter { $0 == longUnbox }
                #expect(
                    boxLongNonnullCalls.count == 4,
                    "arr[0] += 5L on Array<Long> should box array construction and the stored result as non-null Long. Found \(boxLongNonnullCalls.count)"
                )
                #expect(!unboxLongCalls.isEmpty, "arr[0] += 5L on Array<Long> should unbox the read element as Long. Found \(unboxLongCalls.count)")
            }

            do {
                let callees = try calleeIDs(of: "compoundAssignFloatingPoint")
                // Indexed compound assignments must use the same typed operations as
                // ordinary binary expressions, across boxed and primitive arrays.
                let operations: [KIRBinaryOp] = [.add, .subtract, .multiply, .divide, .modulo]
                for primitive in [PrimitiveType.double, .float, .int] {
                    let arena = KIRArena()
                    let type = sema.types.make(.primitive(primitive, .nonNull))
                    let lhs = arena.appendTemporary(type: type)
                    let rhs = arena.appendTemporary(type: type)
                    let body: [KIRInstruction] = operations.map { op in
                        .binary(op: op, lhs: lhs, rhs: rhs, result: arena.appendTemporary(type: type))
                    }
                    let (reference, declID) = makeModule(body: body, interner: interner, arena: arena)
                    try OperatorLoweringPass().run(module: reference, ctx: makeKIRContext(from: ctx))
                    let expectedCallees = calleeIDs(in: bodyInDecl(declID, module: reference))
                    #expect(expectedCallees.count == operations.count)
                    #expect(Set(expectedCallees).count == operations.count)
                    for expected in expectedCallees {
                        #expect(callees.filter { $0 == expected }.count == (primitive == .int ? 0 : 2))
                    }
                }
            }

            do {
                let callees = try calleeIDs(of: "genericArrayAssign")
                // The erased cast passes the array through; only boxing and the store remain.
                #expect(Set(callees) == [intBox, arrayNames.kkArraySetName])
            }
        }
    }
}
#endif
