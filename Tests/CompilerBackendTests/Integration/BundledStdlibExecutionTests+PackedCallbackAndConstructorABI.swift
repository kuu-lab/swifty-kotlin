import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [true, false])
    func constructorReflectionPreservesPackedVarargArrays(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            try diffCaseSource("reflection_constructor_vararg_arrays.kt", file: #filePath),
            expectedOutput: "2\n2\nkotlin.Array<out kotlin.String>\ntrue\n2\n2\n"
                + "kotlin.IntArray\n2\n5\nkotlin.DoubleArray\n2\n4.0\n",
            moduleName: "ConstructorPackedVarargArrays",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }

    @Test(arguments: [true, false])
    func channelCloseCallbacksPreserveCallableClosureABI(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            try diffCaseSource("coroutine_channel_close_callbacks.kt", file: #filePath),
            expectedOutput: "stored:true\nfirst:true\nsecond:false\nstored-calls:2\n"
                + "literal:true\nliteral-calls:3\nreference:true\nlate:true\n",
            moduleName: "ChannelCloseCallableClosureABI",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }
}
