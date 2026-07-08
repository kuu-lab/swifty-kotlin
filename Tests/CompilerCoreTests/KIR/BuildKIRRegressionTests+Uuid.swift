#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension BuildKIRRegressionTests {
    @Test func testUuidClassApisLowerThroughKotlinSource() throws {
        let source = """
        @file:OptIn(kotlin.uuid.ExperimentalUuidApi::class)

        import kotlin.uuid.Uuid

        fun main(bytes: ByteArray) {
            val nil = Uuid.NIL
            val random = Uuid.random()
            val named = Uuid.nameUUIDFromBytes(bytes)
            val uuid = Uuid.parse("550e8400-e29b-41d4-a716-446655440000")
            val maybeUuid = Uuid.parseOrNull("550e8400-e29b-41d4-a716-446655440000")
            val hexUuid = Uuid.parseHex("550e8400e29b41d4a716446655440000")
            val maybeHexUuid = Uuid.parseHexOrNull("550e8400e29b41d4a716446655440000")
            val dashUuid = Uuid.parseHexDash("550e8400-e29b-41d4-a716-446655440000")
            val maybeDashUuid = Uuid.parseHexDashOrNull("550e8400-e29b-41d4-a716-446655440000")
            val fromLongs = Uuid.fromLongs(uuid.mostSignificantBits, uuid.leastSignificantBits)
            val fromBytes = Uuid.fromByteArray(uuid.toByteArray())
            nil.toString()
            random.toString()
            named.toHexString()
            uuid.toString()
            maybeUuid?.toString()
            hexUuid.toString()
            maybeHexUuid?.toString()
            dashUuid.toString()
            maybeDashUuid?.toString()
            fromLongs.toLongs()
            fromBytes.toByteArray()
            uuid.version()
            uuid.variant()
            Uuid.LEXICAL_ORDER.compare(uuid, nil)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = Set(extractCallees(from: body, interner: ctx.interner))

            for callee in [
                "random",
                "nameUUIDFromBytes",
                "fromLongs",
                "fromByteArray",
                "toByteArray",
            ] {
                #expect(callees.contains(callee), "Uuid.\(callee) should remain Kotlin source-backed")
            }

            #expect(callees.isDisjoint(with: [
                "__kk_uuid_random",
                "__kk_uuid_nameUUIDFromBytes",
                "__kk_uuid_lexicalOrder",
                "__kk_uuid_fromLongs",
            ]))

            let removedRuntimeCallees: Set<String> = [
                "kk_uuid_fromByteArray",
                "kk_uuid_fromLongs",
                "kk_uuid_leastSignificantBits",
                "kk_uuid_lexicalOrder",
                "kk_uuid_mostSignificantBits",
                "kk_uuid_nameUUIDFromBytes",
                "kk_uuid_nil",
                "kk_uuid_parse",
                "kk_uuid_parseHex",
                "kk_uuid_parseHexDash",
                "kk_uuid_parseHexDashOrNull",
                "kk_uuid_parseHexOrNull",
                "kk_uuid_parseOrNull",
                "kk_uuid_random",
                "kk_uuid_toByteArray",
                "kk_uuid_toHexString",
                "kk_uuid_toLongs",
                "kk_uuid_toString",
                "kk_uuid_variant",
                "kk_uuid_version",
            ]
            #expect(
                callees.isDisjoint(with: removedRuntimeCallees),
                "Uuid pure logic should be Kotlinized; unexpected removed callees: \(callees.intersection(removedRuntimeCallees))"
            )
        }
    }

    /// KSP-476: java.util.UUID.toKotlinUuid() and the ByteArray.getUuid/uuid/putUuid
    /// extensions are the last pieces of the kotlin.uuid surface. toKotlinUuid still
    /// needs a native bridge (java.util.UUID interop); the ByteArray extensions are
    /// pure Kotlin now, built on Uuid.fromLongs and the real
    /// mostSignificantBits/leastSignificantBits stored properties.
    @Test func testUuidByteArrayExtensionsAndJavaInteropLowerThroughKotlinSource() throws {
        let source = """
        @file:OptIn(kotlin.uuid.ExperimentalUuidApi::class)

        import kotlin.uuid.Uuid
        import kotlin.uuid.getUuid
        import kotlin.uuid.putUuid
        import kotlin.uuid.uuid

        fun main(bytes: ByteArray, javaUuid: java.util.UUID) {
            val fromJava = javaUuid.toKotlinUuid()
            val viaGetUuid = bytes.getUuid(0)
            val viaUuid = bytes.uuid(0)
            bytes.putUuid(0, fromJava)
            fromJava.toString()
            viaGetUuid.toString()
            viaUuid.toString()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = Set(extractCallees(from: body, interner: ctx.interner))

            for callee in ["toKotlinUuid", "getUuid", "uuid", "putUuid"] {
                #expect(callees.contains(callee), "kotlin.uuid.\(callee) should remain Kotlin source-backed")
            }

            #expect(callees.isDisjoint(with: [
                "kk_byteArray_putUuid",
                "kk_byteArray_uuid",
                "kk_uuid_getUuid",
                "kk_uuid_toKotlinUuid",
                "__kk_uuid_toKotlinUuid",
            ]))
        }
    }

    @Test func testUuidSizeConstantsLowerToImmediateConstants() throws {
        let source = """
        @file:OptIn(kotlin.uuid.ExperimentalUuidApi::class)

        import kotlin.uuid.Uuid

        fun main(): Int {
            val bits = Uuid.SIZE_BITS
            val bytes = Uuid.SIZE_BYTES
            return bits + bytes
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let intConstants = body.compactMap { instruction -> Int64? in
                guard case let .constValue(_, value) = instruction,
                      case let .intLiteral(intValue) = value
                else {
                    return nil
                }
                return intValue
            }

            #expect(intConstants.contains(128), "Expected Uuid.SIZE_BITS to lower as int literal 128")
            #expect(intConstants.contains(16), "Expected Uuid.SIZE_BYTES to lower as int literal 16")
        }
    }

    @Test func testABILoweringMarksResidualUuidBridgesAsNonThrowing() {
        let pass = ABILoweringPass()
        let interner = StringInterner()
        let callees = pass.nonThrowingCallees(interner: interner)

        for callee in [
            "__kk_uuid_random",
            "__kk_uuid_nameUUIDFromBytes",
            "__kk_uuid_lexicalOrder",
            "__kk_uuid_fromLongs",
            "__kk_uuid_toKotlinUuid",
        ] {
            #expect(
                callees.contains(interner.intern(callee)),
                "\(callee) should not receive an outThrown slot during ABI lowering"
            )
        }

        for removed in [
            "kk_uuid_random",
            "kk_uuid_parse",
            "kk_uuid_toString",
            "kk_uuid_fromLongs",
            "kk_uuid_toKotlinUuid",
            "kk_byteArray_putUuid",
            "kk_byteArray_uuid",
            "kk_uuid_getUuid",
        ] {
            #expect(!(callees.contains(interner.intern(removed))), "\(removed) should not remain in UUID ABI")
        }
    }
}
#endif
