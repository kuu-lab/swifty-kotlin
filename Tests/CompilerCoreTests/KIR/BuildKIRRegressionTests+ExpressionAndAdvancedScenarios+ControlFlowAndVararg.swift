#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension BuildKIRRegressionTests {
    @Test func testControlFlowAndVarargKIR() throws {
        let sources = [
            """
            package sample0
            fun pick0(flag: Boolean): Int {
                if (flag) { return 1 } else { return 2 }
            }
            """,
            """
            package sample1
            fun classify1(x: Int): Int {
                when (x) {
                    1 -> return 10
                    2 -> return 20
                    else -> return 30
                }
            }
            """,
            """
            package sample2
            fun earlyReturn2(flag: Boolean): Int {
                if (flag) {
                    return 42
                    val x = 99
                }
                return 0
            }
            """,
            """
            package sample3
            fun safeDivide3(a: Int, b: Int): Int {
                try {
                    return a / b
                } catch (e: Any) {
                    return 0
                }
            }
            """,
            """
            package sample4
            fun branch4(flag: Boolean): Int {
                val x = if (flag) 1 else 2
                return x
            }
            """,
            """
            package sample5
            fun pick5(x: Int): Int {
                return when (x) {
                    1 -> 10
                    2 -> 20
                    else -> 0
                }
            }
            """,
            """
            package sample6
            fun tagged6(vararg nums: Int, tail: Int): Int = tail
            fun main6() = tagged6(10, 20, tail = 99)
            """,
            """
            package sample7
            fun pick7(flag: Boolean): Int = if (flag) 1 else 2
            """,
            """
            package sample8
            fun pick8(x: Int): Int = when (x) { 1 -> 10, 2 -> 20, else -> 0 }
            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths, emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let interner = ctx.interner

            do {
                let body = try findKIRFunctionBody(named: "pick0", in: module, interner: interner)
                let returnValues = body.compactMap { instruction -> KIRExprID? in
                    guard case let .returnValue(id) = instruction else { return nil }
                    return id
                }
                #expect(returnValues.count == 2)
            }

            do {
                let body = try findKIRFunctionBody(named: "classify1", in: module, interner: interner)
                let returnValues = body.compactMap { instruction -> KIRExprID? in
                    guard case let .returnValue(id) = instruction else { return nil }
                    return id
                }
                #expect(returnValues.count >= 3)

                var deadCopyAfterReturn = false
                for (index, instruction) in body.enumerated() {
                    if case .returnValue = instruction {
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
                #expect(!deadCopyAfterReturn)
            }

            do {
                let body = try findKIRFunctionBody(named: "earlyReturn2", in: module, interner: interner)
                let has99 = body.contains { instruction in
                    guard case let .constValue(_, value) = instruction else { return false }
                    if case .intLiteral(99) = value { return true }
                    return false
                }
                #expect(!has99)
            }

            do {
                let body = try findKIRFunctionBody(named: "safeDivide3", in: module, interner: interner)
                let returnValues = body.compactMap { instruction -> KIRExprID? in
                    guard case let .returnValue(id) = instruction else { return nil }
                    return id
                }
                #expect(returnValues.count >= 2)

                let callees = extractCallees(from: body, interner: interner)
                #expect(callees.contains("kk_throwable_is_cancellation"))
                let throwFlags = extractThrowFlags(from: body, interner: interner)
                #expect(throwFlags["kk_throwable_is_cancellation"]?.allSatisfy { $0 == false } == true)
            }

            do {
                let body = try findKIRFunctionBody(named: "branch4", in: module, interner: interner)
                let hasJump = body.contains { if case .jump = $0 { return true }; return false }
                let hasLabel = body.contains { if case .label = $0 { return true }; return false }
                #expect(hasJump)
                #expect(hasLabel)
            }

            do {
                let body = try findKIRFunctionBody(named: "pick5", in: module, interner: interner)
                let labelCount = body.filter { if case .label = $0 { return true }; return false }.count
                let jumpCount = body.filter { instruction in
                    if case .jump = instruction { return true }
                    return false
                }.count
                #expect(labelCount >= 2)
                #expect(jumpCount >= 2)
            }

            do {
                let body = try findKIRFunctionBody(named: "main6", in: module, interner: interner)
                let callNames = extractCallees(from: body, interner: interner)
                #expect(callNames.contains("kk_array_new"))
                #expect(callNames.contains("kk_array_set"))
            }

            do {
                let body = try findKIRFunctionBody(named: "pick7", in: module, interner: interner)
                let labelCount = body.filter { if case .label = $0 { return true }; return false }.count
                let jumpCount = body.filter { instruction in
                    if case .jump = instruction { return true }
                    if case .jumpIfEqual = instruction { return true }
                    return false
                }.count
                #expect(labelCount >= 2)
                #expect(jumpCount >= 2)
            }

            do {
                let body = try findKIRFunctionBody(named: "pick8", in: module, interner: interner)
                let labelCount = body.filter { if case .label = $0 { return true }; return false }.count
                #expect(labelCount >= 3)
            }
        }
    }
}
#endif
