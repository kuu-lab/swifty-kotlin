#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct LateinitKIRTests {
    @Test func testLateinitReadEmitsGetOrThrowCall() throws {
        let source = """
        class Box {
            lateinit var name: String
            fun read(): String = name
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            #expect(!(ctx.diagnostics.hasError),
                           "lateinit read should compile without errors: \(ctx.diagnostics.diagnostics.map(\.message))")

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "read", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)

            #expect(callees.contains("kk_lateinit_get_or_throw"),
                          "Expected kk_lateinit_get_or_throw in read body, got: \(callees)")
        }
    }

    @Test func testLateinitIsInitializedEmitsRuntimeCheck() throws {
        let source = """
        class Box {
            lateinit var name: String
            fun ready(): Boolean = ::name.isInitialized
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            #expect(!(ctx.diagnostics.hasError),
                           "lateinit isInitialized should compile without errors: \(ctx.diagnostics.diagnostics.map(\.message))")

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "ready", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)

            #expect(callees.contains("kk_lateinit_is_initialized"),
                          "Expected kk_lateinit_is_initialized in ready body, got: \(callees)")
        }
    }

    @Test func testKProperty0IsInitializedRejectsValueReceiver() throws {
        let source = """
        import kotlin.reflect.KProperty0

        var value: Int = 7

        fun invalid(property: KProperty0<*>): Boolean = property.isInitialized
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(
                ctx.diagnostics.diagnostics.contains { diagnostic in
                    diagnostic.code == "KSWIFTK-SEMA-LATEINIT"
                        && diagnostic.message.contains("property literals")
                },
                "KProperty0.isInitialized should reject value receivers: \(ctx.diagnostics.diagnostics.map { $0.message })"
            )
        }
    }
}
#endif
