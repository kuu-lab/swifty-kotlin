#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct NumericNarrowPrimitiveTimesDivRemMemberCallTests {
    @Test
    func testByteAndShortTimesDivRemMemberCalls() throws {
        let source = """
        package sample

        fun sample(byte: Byte, short: Short, nullableByte: Byte?, nullableShort: Short?) {
            val byteTimes: Int = byte.times(3)
            val byteDiv: Int = byte.div(2)
            val byteRem: Int = byte.rem(4)
            val shortTimes: Int = short.times(3)
            val shortDiv: Int = short.div(2)
            val shortRem: Int = short.rem(4)

            val nullableByteTimes: Int? = nullableByte?.times(3)
            val nullableByteDiv: Int? = nullableByte?.div(2)
            val nullableByteRem: Int? = nullableByte?.rem(4)
            val nullableShortTimes: Int? = nullableShort?.times(3)
            val nullableShortDiv: Int? = nullableShort?.div(2)
            val nullableShortRem: Int? = nullableShort?.rem(4)
        }
        """

        try withTemporaryFiles(contents: [source]) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            let diagnostics = diagnosticsForPath(paths[0], in: ctx)
            #expect(diagnostics.isEmpty, "Expected Byte/Short times, div, and rem calls to resolve: \(diagnostics)")
        }
    }
}

#endif
