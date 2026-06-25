@testable import CompilerCore
import Foundation
import XCTest

extension BuildKIRRegressionTests {

    func testIntArrayOfFactoryLowersToKkArrayOf() throws {
        let source = """
        fun make() = intArrayOf(1, 2, 3)
        fun main(): Int {
            val arr = make()
            return arr.size
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let makeBody = try findKIRFunctionBody(named: "make", in: module, interner: ctx.interner)
            let callNames = extractCallees(from: makeBody, interner: ctx.interner)

            XCTAssertTrue(
                callNames.contains("kk_array_of"),
                "intArrayOf must lower to kk_array_of; got: \(callNames)"
            )
            XCTAssertFalse(
                callNames.contains("intArrayOf"),
                "intArrayOf call should have been rewritten; got: \(callNames)"
            )
        }
    }

    func testByteArrayOfFactoryLowersToKkArrayOf() throws {
        let source = """
        fun make() = byteArrayOf(1.toByte(), 127.toByte())
        fun main(): Int {
            val arr = make()
            return arr.size
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let makeBody = try findKIRFunctionBody(named: "make", in: module, interner: ctx.interner)
            let callNames = extractCallees(from: makeBody, interner: ctx.interner)

            XCTAssertTrue(
                callNames.contains("kk_array_of"),
                "byteArrayOf must lower to kk_array_of; got: \(callNames)"
            )
        }
    }

    func testCharArrayOfFactoryLowersToKkArrayOf() throws {
        let source = """
        fun make() = charArrayOf('a', 'b', 'c')
        fun main(): Int {
            val arr = make()
            return arr.size
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let makeBody = try findKIRFunctionBody(named: "make", in: module, interner: ctx.interner)
            let callNames = extractCallees(from: makeBody, interner: ctx.interner)

            XCTAssertTrue(
                callNames.contains("kk_array_of"),
                "charArrayOf must lower to kk_array_of; got: \(callNames)"
            )
        }
    }

    func testIntArrayLambdaConstructorLowersToArrayNewAndArraySet() throws {
        let source = """
        fun make() = IntArray(3) { it * 2 }
        fun main(): Int {
            val arr = make()
            return arr.size
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let makeBody = try findKIRFunctionBody(named: "make", in: module, interner: ctx.interner)
            let callNames = extractCallees(from: makeBody, interner: ctx.interner)

            XCTAssertTrue(
                callNames.contains("kk_array_new"),
                "IntArray(n) { init } must emit kk_array_new; got: \(callNames)"
            )
            XCTAssertTrue(
                callNames.contains("kk_array_set"),
                "IntArray(n) { init } must emit kk_array_set in the fill loop; got: \(callNames)"
            )

            let throwFlags = extractThrowFlags(from: makeBody, interner: ctx.interner)
            XCTAssertEqual(
                throwFlags["kk_array_new"]?.allSatisfy { $0 == false },
                true,
                "kk_array_new inside constructor must be non-throwing"
            )
        }
    }

    func testByteArrayLambdaConstructorLowersToArrayNewAndArraySet() throws {
        let source = """
        fun make() = ByteArray(4) { (it + 1).toByte() }
        fun main(): Int {
            val arr = make()
            return arr.size
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let makeBody = try findKIRFunctionBody(named: "make", in: module, interner: ctx.interner)
            let callNames = extractCallees(from: makeBody, interner: ctx.interner)

            XCTAssertTrue(
                callNames.contains("kk_array_new"),
                "ByteArray(n) { init } must emit kk_array_new; got: \(callNames)"
            )
            XCTAssertTrue(
                callNames.contains("kk_array_set"),
                "ByteArray(n) { init } must emit kk_array_set; got: \(callNames)"
            )
        }
    }

    func testListToIntArrayLowersToRuntimeCall() throws {
        let source = """
        fun convert(list: List<Int>) = list.toIntArray()
        fun main(): Int {
            val arr = convert(listOf(10, 20, 30))
            return arr.size
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let convertBody = try findKIRFunctionBody(named: "convert", in: module, interner: ctx.interner)
            let callNames = extractCallees(from: convertBody, interner: ctx.interner)

            XCTAssertTrue(
                callNames.contains("kk_list_toIntArray"),
                "List<Int>.toIntArray() must lower to kk_list_toIntArray; got: \(callNames)"
            )
            XCTAssertFalse(
                callNames.contains("toIntArray"),
                "toIntArray must be fully rewritten; got: \(callNames)"
            )
        }
    }

    func testIntArrayToListLowersToRuntimeCall() throws {
        let source = """
        fun convert(arr: IntArray) = arr.toList()
        fun main(): Int {
            val list = convert(intArrayOf(1, 2))
            return list.size
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let convertBody = try findKIRFunctionBody(named: "convert", in: module, interner: ctx.interner)
            let callNames = extractCallees(from: convertBody, interner: ctx.interner)

            let resolved = callNames.contains("kk_intArray_toList") || callNames.contains("kk_array_toList")
            XCTAssertTrue(
                resolved,
                "IntArray.toList() must lower to a runtime toList call; got: \(callNames)"
            )
            XCTAssertFalse(
                callNames.contains("toList"),
                "toList must be fully rewritten to a runtime call; got: \(callNames)"
            )
        }
    }
}
