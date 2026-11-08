import Testing

extension BundledStdlibExecutionTests {
    /// KUU-4413: the data class's synthetic `copy` member is `.synthetic` like
    /// `componentN` but carries the primary-constructor parameters, so the
    /// component-only whitelist in `emitMemberReflectionRegistration` skipped
    /// it and `KClass.members` never listed `copy`. The JVM includes it.
    @Test(arguments: [false, true])
    func dataClassCopyAppearsInClassMembers(fromArtifact: Bool) throws {
        try compileAndRunKotlin(
            """
            data class Point(val name: String, var age: Int)
            data class Single(val e: Int)
            class Regular(val x: Int) {
                fun f(): Int = x
            }

            fun main() {
                println(Point::class.members.map { it.name }.sorted())
                println(Single::class.members.map { it.name }.sorted())
                println(Regular::class.members.map { it.name }.sorted())
                println(Point::class.members.first { it.name == "copy" }.returnType)
            }
            """,
            expectedOutput: """
            [age, component1, component2, copy, equals, hashCode, name, toString]
            [component1, copy, e, equals, hashCode, toString]
            [equals, f, hashCode, toString, x]
            Point
            """ + "\n",
            moduleName: "DataClassCopyReflection",
            allowDefaultStdlibLibrary: fromArtifact
        )
    }
}
