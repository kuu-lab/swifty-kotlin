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
}

#endif
