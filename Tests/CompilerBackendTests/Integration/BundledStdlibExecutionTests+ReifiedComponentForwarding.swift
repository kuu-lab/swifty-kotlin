import Testing

extension BundledStdlibExecutionTests {
    @Test
    func reifiedComponentForwardingKeepsCapturedAndIntersectionTypes() throws {
        try compileAndRunKotlin(
            try diffCaseSource("reflection_reified_component_forwarding.kt", file: #filePath),
            expectedOutput: "captured:0\nintersection:0\nerased:IAE\ncaptured-nested:0\n",
            moduleName: "ReifiedComponentForwarding"
        )
    }
}
