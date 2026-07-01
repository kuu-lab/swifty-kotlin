#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

// MARK: - Helper to extract isSuperCall flags from KIR instructions

private func extractSuperCallFlags(
    from body: [KIRInstruction],
    interner: StringInterner
) -> [(callee: String, isSuperCall: Bool, qualifiedSuperType: SymbolID?)] {
    body.compactMap { instruction -> (callee: String, isSuperCall: Bool, qualifiedSuperType: SymbolID?)? in
        guard case let .call(_, callee, _, _, _, _, isSuperCall, qualifiedSuperType) = instruction else {
            return nil
        }
        return (interner.resolve(callee), isSuperCall, qualifiedSuperType)
    }
}

/// Find all KIR function bodies matching the given name (handles overrides with same name).
private func findAllKIRFunctionBodies(
    named name: String,
    in module: KIRModule,
    interner: StringInterner
) -> [[KIRInstruction]] {
    findAllKIRFunctions(in: module).compactMap { function -> [KIRInstruction]? in
        return interner.resolve(function.name) == name ? function.body : nil
    }
}

/// Collect isSuperCall flags across ALL functions with the given name.
private func extractSuperCallFlagsAcrossOverrides(
    named name: String,
    in module: KIRModule,
    interner: StringInterner
) -> [(callee: String, isSuperCall: Bool)] {
    findAllKIRFunctionBodies(named: name, in: module, interner: interner)
        .flatMap { extractSuperCallFlags(from: $0, interner: interner) }
        .map { ($0.callee, $0.isSuperCall) }
}

@Suite @MainActor
struct SuperCallAndQualifiedThisTests {
    // MARK: - super.method() isSuperCall flag

    @Test func testSuperCallProducesIsSuperCallTrueInKIR() throws {
        let source = """
        open class Base {
            open fun greet(): String = "hello"
        }
        class Child : Base() {
            override fun greet(): String = super.greet()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            #expect(!(ctx.diagnostics.hasError),
                           "Expected super call program to compile without sema errors, got: \(ctx.diagnostics.diagnostics.map(\.message))")

            let module = try #require(ctx.kir)
            // Both Base.greet and Child.greet exist; search across all overrides
            let flags = extractSuperCallFlagsAcrossOverrides(named: "greet", in: module, interner: ctx.interner)

            // The overridden greet() should contain a call to greet with isSuperCall=true
            let superGreetCall = flags.first { $0.callee == "greet" && $0.isSuperCall }
            #expect(superGreetCall != nil, "Expected a call to 'greet' with isSuperCall=true in Child.greet() body, got: \(flags)")
        }
    }

    @Test func testRegularMemberCallHasIsSuperCallFalse() throws {
        let source = """
        class Greeter {
            fun greet(): String = "hello"
            fun callGreet(): String = this.greet()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            #expect(!(ctx.diagnostics.hasError),
                           "Expected regular call program to compile without errors.")

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "callGreet", in: module, interner: ctx.interner)
            let flags = extractSuperCallFlags(from: body, interner: ctx.interner)

            let greetCall = flags.first { $0.callee == "greet" }
            #expect(greetCall != nil, "Expected a call to 'greet' in callGreet() body.")
            #expect(!(greetCall?.isSuperCall ?? true),
                           "Expected this.greet() to have isSuperCall=false, got: \(flags)")
        }
    }

    // MARK: - isSuperCall through lowering pipeline

    @Test func testIsSuperCallSurvivesFullLoweringPipeline() throws {
        let source = """
        open class Base {
            open fun greet(): String = "hello"
        }
        class Child : Base() {
            override fun greet(): String = super.greet()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)

            #expect(!(ctx.diagnostics.hasError),
                           "Expected super call program to compile and lower without errors.")

            let module = try #require(ctx.kir)
            // Search across all overrides of 'greet'
            let flags = extractSuperCallFlagsAcrossOverrides(named: "greet", in: module, interner: ctx.interner)

            // After full lowering, the super call should still have isSuperCall=true
            let superGreetCall = flags.first { $0.callee == "greet" && $0.isSuperCall }
            #expect(superGreetCall != nil,
                            "Expected isSuperCall=true to survive full lowering pipeline, got: \(flags)")
        }
    }

    @Test func testIsSuperCallPreservedThroughABILowering() throws {
        // Use Any parameter to force ABI boxing pass to rewrite the call
        let source = """
        open class Base {
            open fun process(x: Any): Any = x
        }
        class Child : Base() {
            override fun process(x: Any): Any = super.process(x)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)

            #expect(!(ctx.diagnostics.hasError),
                           "Expected ABI boxing super call to compile and lower without errors.")

            let module = try #require(ctx.kir)
            // Search across all overrides of 'process'
            let flags = extractSuperCallFlagsAcrossOverrides(named: "process", in: module, interner: ctx.interner)

            let processCall = flags.first { $0.callee == "process" && $0.isSuperCall }
            #expect(processCall != nil,
                            "Expected isSuperCall=true to survive ABI lowering with boxing, got: \(flags)")
        }
    }

    // MARK: - Qualified this@Label

    @Test func testQualifiedThisResolvesToOuterClassType() throws {
        let source = """
        class Outer {
            fun getOuter(): Outer = this
            inner class Inner {
                fun getOuter(): Outer = this@Outer
            }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runSema(ctx)

            // Should compile without errors — this@Outer resolves to Outer type
            let hasError = ctx.diagnostics.diagnostics.contains { $0.severity == .error }
            #expect(!(hasError),
                           "Expected this@Outer in nested class to resolve without errors, got: \(ctx.diagnostics.diagnostics.map(\.message))")
        }
    }

    @Test func testUnresolvedQualifiedThisEmitsDiagnostic() throws {
        let source = """
        class Outer {
            class Inner {
                fun bad(): Int = this@NonExistent
            }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runSema(ctx)

            assertHasDiagnostic("KSWIFTK-SEMA-0053", in: ctx)
        }
    }

    // MARK: - KIR dump format

    @Test func testKIRDumpFormatIncludesSuperTag() throws {
        let source = """
        open class Base {
            open fun greet(): String = "hello"
        }
        class Child : Base() {
            override fun greet(): String = super.greet()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)

            // The full dump should include 'super=1' for the super.greet() call
            let dumpOutput = module.dump(interner: ctx.interner, symbols: ctx.sema?.symbols)
            #expect(dumpOutput.contains("super=1"),
                          "Expected KIR dump to contain 'super=1' for super call, got:\n\(dumpOutput)")
        }
    }

    @Test func testKIRDumpDoesNotIncludeSuperTagForRegularCalls() throws {
        let source = """
        fun greet(): String = "hello"
        fun main() = greet()
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let dumpOutput = module.dump(interner: ctx.interner, symbols: ctx.sema?.symbols)
            #expect(!(dumpOutput.contains("super=1")),
                           "Regular call dump should not contain 'super=1', got:\n\(dumpOutput)")
        }
    }

    @Test func testKIRDumpFormatIncludesQualifiedSuperTag() throws {
        let source = """
        interface Left {
            fun default1(): String = "left"
        }
        interface Right {
            fun default1(): String = "right"
        }
        class Child : Left, Right {
            fun callLeft(): String = super<Left>.default1()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)

            // The full dump should include 'qualifiedSuper=' for the super<Left>.default1() call
            let dumpOutput = module.dump(interner: ctx.interner, symbols: ctx.sema?.symbols)
            #expect(dumpOutput.contains("qualifiedSuper="),
                          "Expected KIR dump to contain 'qualifiedSuper=' for qualified super call, got:\n\(dumpOutput)")
        }
    }
}
#endif
