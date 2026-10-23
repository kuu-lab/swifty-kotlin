import Testing

extension BundledStdlibExecutionTests {
    /// KUU-2957: boxed singletons must keep JVM identity semantics —
    /// `===`/`==` across Any/Any? boundaries for Unit, Boolean, Char,
    // enum entries, and JVM-cached primitives.
    @Test(arguments: [true, false])
    func testBoxedUnitIdentity(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            """
            fun bar(): Unit {}
            fun baz(): Any? = bar()
            fun quux(): Unit? = bar()

            fun main() {
                // JetBrains unit/kt4212.kt: Unit? vs Any? must agree
                if (baz() != quux()) { println("Fail"); return }

                val u: Unit = bar()
                val ua: Any = u
                val uq: Unit? = bar()
                println(ua === Unit)
                println(baz() == quux())
                println(uq === Unit)
                println(uq === ua)
                println((u as Any) === (Unit as Any))
                println("OK")
            }
            """,
            expectedOutput: "true\ntrue\ntrue\ntrue\ntrue\nOK\n",
            moduleName: "BoxedUnitIdentity",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }

    @Test(arguments: [true, false])
    func testBoxedBooleanAndCharIdentity(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            """
            fun main() {
                fun boolCheck(x: Any) = x === true
                println(boolCheck(true))
                val b: Boolean = true
                val ba: Any = b
                println(ba === b)
                println(ba !== true)

                val c: Char = 'a'
                val ca: Any = c
                println(ca === c)
                println(('\\u007F' as Any) === ('\\u007F' as Any))
                println(('\\u0080' as Any) === ('\\u0080' as Any))
            }
            """,
            expectedOutput: "true\ntrue\nfalse\ntrue\ntrue\nfalse\n",
            moduleName: "BoxedBooleanCharIdentity",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }

    @Test(arguments: [true, false])
    func testBoxedEnumSingletonIdentity(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            """
            enum class E { A, B, C }
            enum class F { A, B }

            fun ga(): Any = E.A
            fun gf(): F = F.A
            fun same(x: Any?, y: Any?) = x === y

            fun main() {
                val e: E = E.A
                val e2: E? = E.A
                val en: E? = null
                val a: Any = E.A
                val nullableA: Any? = E.A
                val nullableB: Any? = E.A

                println(a === e)
                println(a === ga())          // repeated Any boxing -> same entry
                println(same(E.A, E.A))
                println(nullableA === nullableB)
                println(e2 === a)
                println(e2 == a)
                println(en === a)
                println(e2 == null)
                println(en == null)
                println((e as Any) == gf())  // different enum class -> false
                println(e == a)
                println(e2 == a)
                println(en == a)

                // values()/entries/valueOf resolve to the same entry box
                println(E.values()[0] === E.A)
                println(E.entries[0] === E.A)
                println(E.valueOf("A") === E.A)
            }
            """,
            expectedOutput: "true\ntrue\ntrue\ntrue\ntrue\ntrue\nfalse\nfalse\ntrue\nfalse\ntrue\ntrue\nfalse\ntrue\ntrue\ntrue\n",
            moduleName: "BoxedEnumIdentity",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }

    @Test(arguments: [true, false])
    func testBoxedEnumCollectionsAndWhen(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            """
            enum class E { A, B, C }

            fun main() {
                val e: E = E.A
                val e2: E? = E.A
                val en: E? = null

                val l = listOf(E.A, E.B)
                println(l[0] === E.A)
                println(l.contains(E.A))
                println(l.contains(e2))
                println(mapOf(E.A to 1)[E.A])
                println(setOf(E.A, E.A, E.B).size)
                println(E.values()[0] === E.A)
                println(E.valueOf("A") === E.A)
                println(listOf(E.A) == listOf(E.A))
                println(listOf(E.A) == listOf(E.B))

                println(when (e) { E.A -> "a"; else -> "other" })
                println(when (e2) { E.A -> "a"; else -> "other" })
                println(when (en) { E.A -> "a"; null -> "null"; else -> "other" })
            }
            """,
            expectedOutput: "true\ntrue\ntrue\n1\n2\ntrue\ntrue\ntrue\nfalse\na\na\nnull\n",
            moduleName: "BoxedEnumCollections",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }
}
