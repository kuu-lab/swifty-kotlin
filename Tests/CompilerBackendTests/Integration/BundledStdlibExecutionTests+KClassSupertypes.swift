import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [false, true])
    func builtinDirectSupertypes(fromArtifact: Bool) throws {
        try compileAndRunKotlin(
            try diffCaseSource("kclass_builtin_direct_supertypes.kt", file: #filePath),
            expectedOutput: """
            [kotlin.Number, kotlin.Comparable<kotlin.Byte>, java.io.Serializable]
            [kotlin.Number, kotlin.Comparable<kotlin.Short>, java.io.Serializable]
            [kotlin.Number, kotlin.Comparable<kotlin.Int>, java.io.Serializable]
            [kotlin.Number, kotlin.Comparable<kotlin.Long>, java.io.Serializable]
            [kotlin.Number, kotlin.Comparable<kotlin.Float>, java.io.Serializable]
            [kotlin.Number, kotlin.Comparable<kotlin.Double>, java.io.Serializable]
            [kotlin.Any, java.io.Serializable]
            [kotlin.Comparable<kotlin.Char>, java.io.Serializable, kotlin.Any]
            [kotlin.Comparable<kotlin.Boolean>, java.io.Serializable, kotlin.Any]
            [kotlin.Comparable<kotlin.String>, kotlin.CharSequence, java.io.Serializable, kotlin.Any]
            [kotlin.Comparable<kotlin.UInt>, kotlin.Any]
            [kotlin.Any, kotlin.Cloneable, java.io.Serializable]
            true
            true
            true
            false
            """ + "\n",
            moduleName: "KUU2175BuiltinDirectSupertypes",
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
            3
            2
            [P, I1, I2]
            [kotlin.Number, kotlin.Comparable<kotlin.Int>, java.io.Serializable]
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
