#if canImport(Testing)
@testable import CompilerCore
import Testing

extension BuildKIRRegressionTests {
    @Test func testUuidClassApisLowerThroughKotlinSource() throws {
        let source = """
        @file:OptIn(kotlin.uuid.ExperimentalUuidApi::class)

        import kotlin.uuid.Uuid

        fun main() {
            val nil = Uuid.NIL
            val random = Uuid.random()
            val uuid = Uuid.parse("550e8400-e29b-41d4-a716-446655440000")
            val maybeUuid = Uuid.parseOrNull("550e8400-e29b-41d4-a716-446655440000")
            val hexUuid = Uuid.parseHex("550e8400e29b41d4a716446655440000")
            val maybeHexUuid = Uuid.parseHexOrNull("550e8400e29b41d4a716446655440000")
            val dashUuid = Uuid.parseHexDash("550e8400-e29b-41d4-a716-446655440000")
            val maybeDashUuid = Uuid.parseHexDashOrNull("550e8400-e29b-41d4-a716-446655440000")
            val longsSum = uuid.toLongs { msb, lsb -> msb + lsb }
            val fromLongs = Uuid.fromLongs(0x550e8400e29b41d4L, 0xa716446655440000uL.toLong())
            val fromBytes = Uuid.fromByteArray(uuid.toByteArray())
            val uBytes = uuid.toUByteArray()
            val fromUBytes = Uuid.fromUByteArray(uBytes)
            val fromULongs = Uuid.fromULongs(0x550e8400e29b41d4uL, 0xa716446655440000uL)
            val v4 = Uuid.generateV4()
            val uLongsSum = uuid.toULongs { msb, lsb -> msb + lsb }
            nil.toString()
            random.toString()
            uuid.toString()
            maybeUuid?.toString()
            hexUuid.toString()
            maybeHexUuid?.toString()
            dashUuid.toString()
            maybeDashUuid?.toString()
            longsSum.toString()
            fromLongs.toString()
            fromBytes.toByteArray()
            uBytes.size
            fromUBytes.toString()
            fromULongs.toString()
            v4.toString()
            uLongsSum.toString()
            uuid.toHexDashString()
            uuid.compareTo(nil)
        }
        """

        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)

        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
        let callees = Set(extractCallees(from: body, interner: ctx.interner))

        for callee in [
            "random",
            "fromLongs",
            "fromULongs",
            "fromByteArray",
            "fromUByteArray",
            "toByteArray",
            "toUByteArray",
            "toLongs",
            "toULongs",
            "toHexDashString",
            "generateV4",
            "compareTo",
        ] {
            #expect(callees.contains(callee), "Uuid.\(callee) should remain Kotlin source-backed")
            try expectSourceBackedCalls(named: ctx.interner.intern(callee), in: body, context: ctx)
        }

        #expect(callees.isDisjoint(with: runtimeCallees(in: .uuid)))
        try expectResolvedKIRCallTargets(in: body, context: ctx)
    }

    /// KSP-508: java.util.UUID.toKotlinUuid() and the java.nio.ByteBuffer.getUuid/putUuid
    /// extensions are the last pieces of the kotlin.uuid surface. toKotlinUuid still
    /// needs a native bridge (java.util.UUID interop); the ByteBuffer extensions are
    /// pure Kotlin now, built on Uuid.fromLongs and the real
    /// mostSignificantBits/leastSignificantBits stored properties.
    @Test func testUuidByteBufferExtensionsAndJavaInteropLowerThroughKotlinSource() throws {
        let source = """
        @file:OptIn(kotlin.uuid.ExperimentalUuidApi::class)

        import kotlin.uuid.Uuid
        import kotlin.uuid.getUuid
        import kotlin.uuid.putUuid
        import java.nio.ByteBuffer

        fun main(buf: ByteBuffer, javaUuid: java.util.UUID) {
            val fromJava = javaUuid.toKotlinUuid()
            val viaGetUuid = buf.getUuid(0)
            val viaPut = buf.putUuid(0, fromJava)
            fromJava.toString()
            viaGetUuid.toString()
            viaPut.toString()
        }
        """

        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)

        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
        let callees = Set(extractCallees(from: body, interner: ctx.interner))

        for callee in ["toKotlinUuid", "getUuid", "putUuid"] {
            #expect(callees.contains(callee), "kotlin.uuid.\(callee) should remain Kotlin source-backed")
            try expectSourceBackedCalls(named: ctx.interner.intern(callee), in: body, context: ctx)
        }

        #expect(callees.isDisjoint(with: runtimeCallees(in: .uuid)))
        try expectResolvedKIRCallTargets(in: body, context: ctx)
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

        let ctx = makeContextFromSource(source)
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

    @Test func testABILoweringMarksResidualUuidBridgesAsNonThrowing() {
        let pass = ABILoweringPass()
        let interner = StringInterner()
        let callees = pass.nonThrowingCallees(interner: interner)

        let residualCallees: Set<String> = [
            runtimeCallee(.uuidRandom),
            runtimeCallee(.uuidLexicalOrder),
            runtimeCallee(.uuidFromLongs),
            runtimeCallee(.uuidToKotlinUuid),
        ]
        for callee in residualCallees {
            #expect(
                callees.contains(interner.intern(callee)),
                "\(callee) should not receive an outThrown slot during ABI lowering"
            )
        }

        #expect(Set(callees.map(interner.resolve)).isSubset(of: registeredRuntimeCallees()))
        #expect(Set(callees.map(interner.resolve)).intersection(runtimeCallees(in: .uuid)) == residualCallees)
    }
}
#endif
