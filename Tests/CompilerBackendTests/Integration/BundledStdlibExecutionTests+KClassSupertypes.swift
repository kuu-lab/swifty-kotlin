import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [false, true])
    func builtinDirectSupertypes(fromArtifact: Bool) throws {
        try compileAndRunKotlin(
            try diffCaseSource("kclass_builtin_direct_supertypes.kt", file: #filePath),
            expectedOutput: """
            [kotlin.Number, kotlin.Comparable<kotlin.Byte>]
            [kotlin.Number, kotlin.Comparable<kotlin.Short>]
            [kotlin.Number, kotlin.Comparable<kotlin.Int>]
            [kotlin.Number, kotlin.Comparable<kotlin.Long>]
            [kotlin.Number, kotlin.Comparable<kotlin.Float>]
            [kotlin.Number, kotlin.Comparable<kotlin.Double>]
            [kotlin.Any, java.io.Serializable]
            [kotlin.Comparable<kotlin.Char>, kotlin.Any]
            [kotlin.Comparable<kotlin.Boolean>, kotlin.Any]
            [kotlin.Comparable<kotlin.String>, kotlin.CharSequence, java.io.Serializable, kotlin.Any]
            [kotlin.Comparable<kotlin.UInt>, kotlin.Any]
            [kotlin.Any, kotlin.Cloneable, java.io.Serializable]
            true
            true
            true
            false
            """ + "\n",
            moduleName: "KUU1983BuiltinDirectSupertypes",
            allowDefaultStdlibLibrary: fromArtifact
        )
    }

    @Test(arguments: [false, true])
    func supertypesNestedClassesAndFlags(fromArtifact: Bool) throws {
        try compileAndRunKotlin(
            try diffCaseSource("kclass_supertypes_nested_flags.kt", file: #filePath),
            expectedOutput: """
            3
            2
            2
            2
            [P, I1, I2]
            [kotlin.Number, kotlin.Comparable<kotlin.Int>]
            [I1, kotlin.Any]
            [Nested, Inn]
            [Companion]
            PUBLIC
            true
            true
            true
            true
            false
            """ + "\n",
            moduleName: "KUU1983SupertypesNestedClassesAndFlags",
            allowDefaultStdlibLibrary: fromArtifact
        )
    }
}
