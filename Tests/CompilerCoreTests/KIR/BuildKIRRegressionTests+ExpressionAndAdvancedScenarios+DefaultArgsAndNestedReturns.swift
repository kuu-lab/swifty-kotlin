#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension BuildKIRRegressionTests {
    @Test func testDefaultArgsAndNestedReturnsKIR() throws {
        let sources = [
            """
            package sample0
            fun main0() {
                val parts = "1,2,3".split(",")
                println(parts)
            }
            """,
            """
            package sample1
            fun add1(a: Int, b: Int = 10): Int = a + b
            fun main1() = add1(5, 20)
            """,
            """
            package sample2
            fun withDep2(a: Int, b: Int = a + 1): Int = a + b
            fun main2() = withDep2(10)
            """,
            """
            package sample3
            fun chain3(a: Int = 1, b: Int = a + 10, c: Int = b + 100): Int = a + b + c
            fun main3() = chain3()
            """,
            """
            package sample4
            fun Int.addDefault4(n: Int = this + 1): Int = this + n
            fun main4() = 5.addDefault4()
            """,
            """
            package sample5
            fun compute5(a: Int, b: Int = a + 1): Int = a + b
            fun main5() = compute5(5)
            """,
            """
            package sample6
            fun choose6(flag: Boolean): Int {
                if (flag) { return 1 }
                return 0
            }
            """,
            """
            package sample7
            fun pick7(flag: Boolean): Int {
                if (flag) { return 1 } else { return 2 }
            }
            """,
            """
            package sample8
            fun describe8(x: Int): Int {
                return when (x) {
                    1 -> return 10
                    2 -> return 20
                    else -> 0
                }
            }
            """,
            """
            package sample9
            fun choose9(flag: Boolean): Int {
                if (flag) { return 1 }
                return 0
            }
            """,
            """
            package sample10
            class Holder10 {
                val transform: (Int) -> Int = { it + 1 }
            }
            fun use10(h: Holder10): Int = h.transform(5)
            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths, emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let interner = ctx.interner

            do {
                let body = try findKIRFunctionBody(named: "main0", in: module, interner: interner)
                let callees = extractCallees(from: body, interner: interner)
                #expect(!callees.contains("kk_string_split_flat"))
                #expect(callees.contains("split") || callees.contains("__kk_string_split"))
                #expect(!callees.contains { $0.contains("split$default") })
            }

            do {
                let body = try findKIRFunctionBody(named: "main1", in: module, interner: interner)
                let callees = extractCallees(from: body, interner: interner)
                #expect(callees.contains("add1"))
                #expect(!callees.contains("add1$default"))
            }

            do {
                let mainBody = try findKIRFunctionBody(named: "main2", in: module, interner: interner)
                let mainCallees = extractCallees(from: mainBody, interner: interner)
                #expect(mainCallees.contains("withDep2$default"))

                let stubFunction = findAllKIRFunctions(in: module).compactMap { function -> KIRFunction? in
                    return interner.resolve(function.name) == "withDep2$default" ? function : nil
                }.first
                #expect(stubFunction != nil)
                if let stub = stubFunction {
                    let stubCallees = extractCallees(from: stub.body, interner: interner)
                    #expect(stubCallees.contains("withDep2"))
                    let hasBinaryAdd = stub.body.contains { instruction in
                        guard case let .binary(op, _, _, _) = instruction else { return false }
                        return op == .add
                    }
                    #expect(hasBinaryAdd)
                }
            }

            do {
                let stubFunction = findAllKIRFunctions(in: module).compactMap { function -> KIRFunction? in
                    return interner.resolve(function.name) == "chain3$default" ? function : nil
                }.first
                #expect(stubFunction != nil)
                if let stub = stubFunction {
                    #expect(stub.params.count == 4)
                    var labelOrder: [Int32] = []
                    for instruction in stub.body {
                        if case let .label(id) = instruction {
                            labelOrder.append(id)
                        }
                    }
                    #expect(labelOrder.count == 6)
                    for i in 1 ..< labelOrder.count {
                        #expect(labelOrder[i] > labelOrder[i - 1])
                    }
                }
            }

            do {
                let mainBody = try findKIRFunctionBody(named: "main4", in: module, interner: interner)
                let mainCallees = extractCallees(from: mainBody, interner: interner)
                #expect(mainCallees.contains("addDefault4$default"))

                let stubFunction = findAllKIRFunctions(in: module).compactMap { function -> KIRFunction? in
                    return interner.resolve(function.name) == "addDefault4$default" ? function : nil
                }.first
                #expect(stubFunction != nil)
                if let stub = stubFunction {
                    #expect(stub.params.count >= 3)
                    let stubCallees = extractCallees(from: stub.body, interner: interner)
                    #expect(stubCallees.contains("addDefault4"))
                }
            }

            do {
                let mainBody = try findKIRFunctionBody(named: "main5", in: module, interner: interner)
                let mainCallees = extractCallees(from: mainBody, interner: interner)
                #expect(mainCallees.contains("compute5$default"))

                let callerHasBinaryAdd = mainBody.contains { instruction in
                    guard case let .binary(op, _, _, _) = instruction else { return false }
                    return op == .add
                }
                #expect(!callerHasBinaryAdd)
            }

            do {
                let body = try findKIRFunctionBody(named: "choose6", in: module, interner: interner)
                let returnValues = body.compactMap { instruction -> KIRExprID? in
                    guard case let .returnValue(id) = instruction else { return nil }
                    return id
                }
                #expect(returnValues.count >= 2)
            }

            do {
                let body = try findKIRFunctionBody(named: "pick7", in: module, interner: interner)
                let returnValues = body.compactMap { instruction -> KIRExprID? in
                    guard case let .returnValue(id) = instruction else { return nil }
                    return id
                }
                #expect(returnValues.count >= 2)
            }

            do {
                let body = try findKIRFunctionBody(named: "describe8", in: module, interner: interner)
                let returnValues = body.compactMap { instruction -> KIRExprID? in
                    guard case let .returnValue(id) = instruction else { return nil }
                    return id
                }
                #expect(returnValues.count >= 2)
            }

            do {
                let body = try findKIRFunctionBody(named: "choose9", in: module, interner: interner)
                var foundReturnInBranch = false
                var deadCopyAfterReturn = false
                for (index, instruction) in body.enumerated() {
                    if case .returnValue = instruction {
                        foundReturnInBranch = true
                        var nextIndex = index + 1
                        while nextIndex < body.count {
                            if case .label = body[nextIndex] {
                                nextIndex += 1
                                continue
                            }
                            if case .copy = body[nextIndex] {
                                deadCopyAfterReturn = true
                            }
                            break
                        }
                    }
                }
                #expect(foundReturnInBranch)
                #expect(!deadCopyAfterReturn)
            }

            do {
                let body = try findKIRFunctionBody(named: "use10", in: module, interner: interner)
                let callees = extractCallees(from: body, interner: interner)
                #expect(callees.contains("transform"))
                #expect(!callees.contains("invoke"))
            }
        }
    }
}
#endif
