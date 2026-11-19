#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

@Suite
struct ExpectActualCovariantOverrideReturnTypeTests {
    @Test
    func covariantOverrideOfExpectActualMemberTypeChecks() throws {
        // Regression: Okio 3.16.2's `expect class Buffer` overrides
        // `fun emit(): BufferedSink` with `override fun emit(): Buffer`.
        // Override validation ran before expect/actual linking, so the
        // return-type covariance check could not bridge the two class
        // symbols and reported a false KSWIFTK-SEMA-OVERRIDE-RETURN.
        _ = try semaContext(from: [
            """
            package sample.kmp
            expect interface Greeter {
              fun greet(): Greeter
            }
            expect class Impl : Greeter {
              override fun greet(): Impl
            }
            """,
            """
            package sample.kmp
            actual interface Greeter {
              actual fun greet(): Greeter
            }
            actual class Impl : Greeter {
              actual override fun greet(): Impl = this
            }
            """,
        ])
    }
}
#endif
