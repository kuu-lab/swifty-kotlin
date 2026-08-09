#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct LateinitKIRTests {
    @Test func testLateinitKIREmissions() throws {
        let sources: [String] = [
            """
            class BoxRead {
                lateinit var name: String
                fun read(): String = name
            }
            """,
            """
            class BoxReady {
                lateinit var name: String
                fun ready(): Boolean = ::name.isInitialized
            }
            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths, emit: .kirDump)
            try runToKIR(ctx)

            #expect(!ctx.diagnostics.hasError, "lateinit KIR tests should compile without errors: \(ctx.diagnostics.diagnostics.map(\.message))")

            do {
                let module = try #require(ctx.kir)
                let body = try findKIRFunctionBody(named: "read", in: module, interner: ctx.interner)
                let callees = extractCallees(from: body, interner: ctx.interner)

                #expect(callees.contains("kk_lateinit_get_or_throw"), "Expected kk_lateinit_get_or_throw in read body, got: \(callees)")
            }

            do {
                let module = try #require(ctx.kir)
                let body = try findKIRFunctionBody(named: "ready", in: module, interner: ctx.interner)
                let callees = extractCallees(from: body, interner: ctx.interner)

                #expect(callees.contains("kk_lateinit_is_initialized"), "Expected kk_lateinit_is_initialized in ready body, got: \(callees)")
            }
        }
    }
}
#endif
