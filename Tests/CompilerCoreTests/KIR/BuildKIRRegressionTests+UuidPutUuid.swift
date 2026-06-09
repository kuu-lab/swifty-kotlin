// STDLIB-UUID-FN-002: putUuid / uuid(at:) KIR lowering regression tests.
// Verifies that ByteArray.putUuid and ByteArray.uuid(at:) lower to their
// respective runtime callees (kk_byteArray_putUuid, kk_byteArray_uuid).
@testable import CompilerCore
import Foundation
import XCTest

extension BuildKIRRegressionTests {
    func testByteArrayPutUuidLowersToRuntimeCallee() throws {
        let source = """
        @file:OptIn(kotlin.uuid.ExperimentalUuidApi::class)

        import kotlin.uuid.Uuid
        import kotlin.uuid.putUuid

        fun writeUuid(arr: ByteArray, uuid: Uuid) {
            arr.putUuid(0, uuid)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "writeUuid", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)

            XCTAssertTrue(
                callees.contains("kk_byteArray_putUuid"),
                "ByteArray.putUuid must lower to kk_byteArray_putUuid; found callees: \(callees)"
            )
        }
    }

    func testByteArrayUuidAtLowersToRuntimeCallee() throws {
        let source = """
        @file:OptIn(kotlin.uuid.ExperimentalUuidApi::class)

        import kotlin.uuid.Uuid
        import kotlin.uuid.uuid

        fun readUuid(arr: ByteArray): Uuid {
            return arr.uuid(0)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "readUuid", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)

            XCTAssertTrue(
                callees.contains("kk_byteArray_uuid"),
                "ByteArray.uuid(at:) must lower to kk_byteArray_uuid; found callees: \(callees)"
            )
        }
    }

    func testByteArrayPutUuidAndUuidAtRoundTripLowersCorrectly() throws {
        let source = """
        @file:OptIn(kotlin.uuid.ExperimentalUuidApi::class)

        import kotlin.uuid.Uuid
        import kotlin.uuid.putUuid
        import kotlin.uuid.uuid

        fun roundTrip(uuid: Uuid): Uuid {
            val buf = ByteArray(16)
            buf.putUuid(0, uuid)
            return buf.uuid(0)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "roundTrip", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)

            XCTAssertTrue(
                callees.contains("kk_byteArray_putUuid"),
                "round-trip: putUuid must lower to kk_byteArray_putUuid"
            )
            XCTAssertTrue(
                callees.contains("kk_byteArray_uuid"),
                "round-trip: uuid(at:) must lower to kk_byteArray_uuid"
            )
        }
    }
}
