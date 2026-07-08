#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension BuildKIRRegressionTests {
    /// KSP-476: parsing/formatting/version/variant/NIL/LEXICAL_ORDER/toLongs/toByteArray
    /// are pure Kotlin now, built on the six bridges that genuinely need native support
    /// (random/fromLongs/mostSignificantBits/leastSignificantBits/nameUUIDFromBytes/
    /// toKotlinUuid). Those bridges are only called from within the Kotlin-source
    /// wrapper's own body (e.g. `random() = __uuidRandom()`), and at this
    /// frontend-only `.kirDump` stage stdlib function bodies from a different
    /// declaration aren't lowered into the same module — only the call-site's
    /// simple callee name (e.g. "random", "get" for a property getter) is visible
    /// here. Full bridge-call verification lives in RuntimeUuid* tests and
    /// Scripts/diff_cases/uuid_basic.kt (diff_kotlinc).
    @Test func testUuidCompanionAndInstanceCallsCompileAndUseSurvivingBridges() throws {
        let source = """
        @file:OptIn(kotlin.uuid.ExperimentalUuidApi::class)

        import kotlin.uuid.Uuid

        fun main() {
            val nil = Uuid.NIL
            val lexicalOrder = Uuid.LEXICAL_ORDER
            val uuid = Uuid.parse("550e8400-e29b-41d4-a716-446655440000")
            val maybeUuid = Uuid.parseOrNull("550e8400-e29b-41d4-a716-446655440000")
            val hexUuid = Uuid.parseHex("550e8400e29b41d4a716446655440000")
            val maybeHexUuid = Uuid.parseHexOrNull("550e8400e29b41d4a716446655440000")
            val dashUuid = Uuid.parseHexDash("550e8400-e29b-41d4-a716-446655440000")
            val maybeDashUuid = Uuid.parseHexDashOrNull("550e8400-e29b-41d4-a716-446655440000")
            nil.toString()
            uuid.toString()
            maybeUuid?.toString()
            hexUuid.toString()
            maybeHexUuid?.toString()
            dashUuid.toString()
            maybeDashUuid?.toString()
            uuid.toHexString()
            uuid.toLongs()
            uuid.toByteArray()
            uuid.version()
            uuid.variant()
            val msb = uuid.mostSignificantBits
            val lsb = uuid.leastSignificantBits
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)

            #expect(
                callees.contains("get"),
                "Expected mostSignificantBits/leastSignificantBits property getter calls; found: \(callees)"
            )
        }
    }

    @Test func testUuidAdditionalFactoriesUseSurvivingBridges() throws {
        let source = """
        @file:OptIn(kotlin.uuid.ExperimentalUuidApi::class)

        import kotlin.uuid.Uuid

        fun main(bytes: ByteArray) {
            Uuid.random()
            Uuid.nameUUIDFromBytes(bytes)
            Uuid.fromLongs(0L, 1L)
            Uuid.fromByteArray(bytes)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)

            #expect(callees.contains("random"), "Expected Uuid.random call; found: \(callees)")
            #expect(callees.contains("nameUUIDFromBytes"), "Expected Uuid.nameUUIDFromBytes call; found: \(callees)")
            #expect(callees.contains("fromLongs"), "Expected Uuid.fromLongs call; found: \(callees)")
            #expect(callees.contains("fromByteArray"), "Expected Uuid.fromByteArray call; found: \(callees)")
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
            let loadGlobalNames = body.compactMap { instruction -> String? in
                guard case let .loadGlobal(_, symbol) = instruction,
                      let symbolInfo = ctx.sema?.symbols.symbol(symbol)
                else {
                    return nil
                }
                let fqName = symbolInfo.fqName.map { ctx.interner.resolve($0) }.joined(separator: ".")
                return fqName
            }

            #expect(
                intConstants.contains(128),
                "Expected Uuid.SIZE_BITS to lower as int literal 128; load globals: \(loadGlobalNames)"
            )
            #expect(
                intConstants.contains(16),
                "Expected Uuid.SIZE_BYTES to lower as int literal 16; load globals: \(loadGlobalNames)"
            )
            #expect(
                !(extractCallees(from: body, interner: ctx.interner).contains { $0.hasPrefix("kk_uuid_size") }),
                "Uuid size constants must not require runtime ABI calls"
            )
        }
    }

    @Test func testABILoweringMarksUuidSurvivingBridgesAsNonThrowing() {
        let pass = ABILoweringPass()
        let interner = StringInterner()
        let callees = pass.nonThrowingCallees(interner: interner)

        let nonThrowingUuidCallees = [
            "__kk_uuid_random",
            "__kk_uuid_mostSignificantBits",
            "__kk_uuid_leastSignificantBits",
            "__kk_uuid_nameUUIDFromBytes",
            "__kk_uuid_fromLongs",
            "__kk_uuid_toKotlinUuid",
        ]

        for callee in nonThrowingUuidCallees {
            #expect(
                callees.contains(interner.intern(callee)),
                "\(callee) should not receive an outThrown slot during ABI lowering"
            )
        }
    }
}
#endif
