#if canImport(Testing)
import Testing

extension BundledStdlibExecutionTests {
    @Test
    func testCustomRangeToReturningNonStdlibIntRangeSupportsMembership() throws {
        try compileAndRunKotlin(
            try diffCaseSource("custom_range_named_int_range.kt", file: #filePath),
            expectedOutput: "true\nfalse\ntrue\ntrue\nfalse\ntrue\ntrue\n",
            moduleName: "KUU3178CustomRangeToMembership"
        )
    }
}
#endif
