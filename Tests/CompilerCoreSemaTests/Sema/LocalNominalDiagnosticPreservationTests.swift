#if canImport(Testing)
import CompilerCore
@testable import CompilerTestSupport
import Testing

@Suite
struct LocalNominalDiagnosticPreservationTests {
    @Test
    func testLocalNominalDiagnosticsSurviveSpeculativeMemberChecks() throws {
        let sources: [String] = [
            // KUU-4601: an object literal returned by an inferred local-class
            // member must keep its initializer diagnostic after the inferred
            // return check rolls back and retries.
            """
            package rollbacka

            fun probe() {
                class D {
                    val x = f()
                    fun f() = object {
                        val bad: Int = "nope"
                    }
                }
                val y = D().x
            }
            """,
            // inferClassLikeMemberTypes truncates a speculative member-function
            // check; the local class inside it must be re-checked authoritatively.
            """
            package rollbackb

            class C {
                fun f() {
                    class L {
                        val bad: Int = "nope"
                    }
                    val l = L()
                }
            }
            """,
            // The getter-only property path truncates the same speculative member
            // check before the accessor body is checked again.
            """
            package rollbackc

            class C {
                val x: Int
                    get() {
                        class L {
                            val bad: Int = "nope"
                        }
                        return 1
                    }
            }
            """,
            // Companion pre-inference truncates diagnostics for the whole class;
            // local nominals checked inside the companion still need re-checking.
            """
            package rollbackd

            class C {
                companion object {
                    fun f() {
                        class L {
                            val bad: Int = "nope"
                        }
                        val l = L()
                    }
                }
            }
            """,
            // Local typealias diagnostics inside the speculative member-function
            // window must survive the same rollback.
            """
            package rollbacke

            class C {
                fun f() {
                    typealias Bad = Missing
                    val x: Bad? = null
                }
            }
            """,
        ]

        _ = try semaContext(
            from: sources,
            expecting: [
                .error("KSWIFTK-SEMA-0468", containing: "Initializer type mismatch", count: 4),
                .error("KSWIFTK-SEMA-0025", containing: "Unresolved type 'Missing'", count: 1),
            ],
            includeStdlib: false
        )
    }

    @Test
    func testLocalNominalMemberInferredReturnsSurviveRecheck() throws {
        let source = """
        package rollbackf

        class C {
            fun f() {
                class L {
                    fun g() = "ok"
                }
                val s: String = L().g()
            }
        }
        """

        _ = try semaContext(from: source, expecting: [], includeStdlib: false)
    }

    @Test
    func testObjectLiteralInferredMemberPropertiesAreFinalBeforeMemberBodies() throws {
        let source = """
        package objectliteralinferred

        interface IntCursor {
            fun hasNext(): Boolean
            fun next(): Int
        }

        interface CursorSource {
            fun cursor(): IntCursor
        }

        class NumberBox(private val source: CursorSource) {
            fun cursor(): IntCursor = object : IntCursor {
                private val cursor = source.cursor()
                private var index = 0

                override fun hasNext(): Boolean = cursor.hasNext() && index < 3

                override fun next(): Int {
                    if (index < 0) return -1
                    val result = cursor.next() + index
                    index++
                    return result
                }
            }
        }
        """

        _ = try semaContext(from: source, expecting: [], includeStdlib: false)
    }

    @Test
    func testObjectLiteralLateinitPropertyIsValidated() throws {
        let source = """
        package objectliterallateinit

        interface IntCursor {
            fun hasNext(): Boolean
        }

        class Box {
            fun cursor(): IntCursor = object : IntCursor {
                lateinit var value: String = "ready"
                override fun hasNext(): Boolean = true
            }
        }
        """

        _ = try semaContext(
            from: source,
            expecting: [.error("KSWIFTK-SEMA-LATEINIT", containing: "must not have an initializer")],
            includeStdlib: false
        )
    }

    @Test
    func testObjectLiteralTypedGetterReadsLaterLazyProperty() throws {
        let source = """
        package objectliteraltypedlazy

        interface HasValue {
            fun get(): String
        }

        class C {
            fun box(): HasValue = object : HasValue {
                val value: String get() = text
                val text by lazy { "OK" }
                override fun get(): String = value
            }
        }
        """

        _ = try semaContext(from: source, expecting: [], includeStdlib: true)
    }

    @Test
    func testObjectLiteralTypedGetterReadsLaterExtensionProperty() throws {
        let source = """
        package objectliteraltypedextension

        interface HasTag {
            fun get(): String
        }

        class C {
            fun box(): HasTag = object : HasTag {
                val value: String get() = "x".tag
                val String.tag get() = "OK"
                override fun get(): String = value
            }
        }
        """

        _ = try semaContext(from: source, expecting: [], includeStdlib: true)
    }

    @Test
    func testObjectLiteralNestedInnerClassReusesSymbolsAcrossRecheck() throws {
        let source = """
        package objectliteralnestedrecheck

        class Generic<T>(val t: T) {
            fun foo(): T {
                val o1 = object {
                    inner class InnerLocal1 {
                        val captured = t
                        fun bar(): T {
                            val o2 = object {
                                inner class InnerLocal2 {
                                    fun baz(): T = captured
                                }
                            }
                            return o2.InnerLocal2().baz()
                        }
                    }
                }
                return o1.InnerLocal1().bar()
            }
        }
        """

        _ = try semaContext(from: source, expecting: [])
    }
}

#endif
