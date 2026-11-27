#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

extension BuildKIRRegressionTests {
    @Test func testBuildKIRFoldsConstStringTemplateInObjectInitializer() throws {
        let ctx = makeContextFromSource("""
        object A {
            const val a: String = "$"
            val bNonConst = "1234$a"
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")

        try BuildKIRPhase().run(ctx)
        let module = try #require(ctx.kir)
        let initFunction = try #require(
            findAllKIRFunctions(in: module).first {
                ctx.interner.resolve($0.name).hasPrefix("__object_lazy_init_")
            },
            "Expected an __object_lazy_init_ function"
        )
        let callees = extractCallees(from: initFunction.body, interner: ctx.interner)
        #expect(!callees.contains(runtimeCallee(.stringConcatFlat)))
        #expect(initFunction.body.contains { instruction in
            guard case let .constValue(_, value) = instruction,
                  case let .stringLiteral(text) = value
            else { return false }
            return ctx.interner.resolve(text) == "1234$"
        })
    }

    @Test func testBuildKIRKeepsNonConstStringTemplateAsRuntimeConcat() throws {
        let ctx = makeContextFromSource("""
        val a: String = "$"
        object A {
            val bNonConst = "1234$a"
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")

        try BuildKIRPhase().run(ctx)
        let module = try #require(ctx.kir)
        let initFunction = try #require(
            findAllKIRFunctions(in: module).first {
                ctx.interner.resolve($0.name).hasPrefix("__object_lazy_init_")
            },
            "Expected an __object_lazy_init_ function"
        )
        let callees = extractCallees(from: initFunction.body, interner: ctx.interner)
        #expect(callees.contains(runtimeCallee(.stringConcatFlat)))
    }

    @Test func testBuildKIRNonConstStringFoldUsesRuntimeSemantics() throws {
        let ctx = makeContextFromSource("""
        fun main() {
            println("p " + (-0.0 == 0.0))
            println("a " + (0.0 / 0.0 == 0.0 / 0.0))
            println("t ${-0.0f == 0.0f}")
            println("v " + (1u + 2u))
            println("w " + (1uL + 2uL))
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")

        try BuildKIRPhase().run(ctx)
        let module = try #require(ctx.kir)
        let mainFunction = try #require(
            findAllKIRFunctions(in: module).first { ctx.interner.resolve($0.name) == "main" }
        )
        let literals = Set(mainFunction.body.compactMap { instruction -> String? in
            guard case let .constValue(_, value) = instruction,
                  case let .stringLiteral(text) = value
            else { return nil }
            return ctx.interner.resolve(text)
        })
        #expect(literals.isSuperset(of: ["p true", "a false", "t true"]), "\(literals)")
        #expect(literals.isDisjoint(with: ["p false", "a true", "t false", "v 12", "w 12"]), "\(literals)")
    }
}
#endif
