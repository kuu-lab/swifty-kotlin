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

@Suite
struct SuperCallAndQualifiedThisTests {
    // MARK: - super.method() / qualified super isSuperCall flags in KIR

    @Test func testSuperCallAndQualifiedSuperKIR() throws {
        let sources: [String] = [
            """
            open class Base {
                open fun greet(): String = "hello"
            }
            class Child : Base() {
                override fun greet(): String = super.greet()
            }
            """,
            """
            interface Left {
                fun default1(): String = "left"
            }
            interface Right {
                fun default1(): String = "right"
            }
            class Child2 : Left, Right {
                override fun default1(): String = super<Left>.default1()
                fun callLeft(): String = default1()
            }
            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths, emit: .kirDump)
            try runToKIR(ctx)

            #expect(
                !(ctx.diagnostics.hasError),
                "Expected super call programs to compile without sema errors, got: \(ctx.diagnostics.diagnostics.map(\.message))"
            )

            let module = try #require(ctx.kir)

            do {
                let flags = extractSuperCallFlagsAcrossOverrides(named: "greet", in: module, interner: ctx.interner)
                let superGreetCall = flags.first { $0.callee == "greet" && $0.isSuperCall }
                #expect(
                    superGreetCall != nil,
                    "Expected a call to 'greet' with isSuperCall=true in Child.greet() body, got: \(flags)"
                )
            }

            do {
                let dumpOutput = module.dump(interner: ctx.interner, symbols: ctx.sema?.symbols)
                #expect(
                    dumpOutput.contains("super=1"),
                    "Expected KIR dump to contain 'super=1' for super call, got:\n\(dumpOutput)"
                )
                #expect(
                    dumpOutput.contains("qualifiedSuper="),
                    "Expected KIR dump to contain 'qualifiedSuper=' for qualified super call, got:\n\(dumpOutput)"
                )
            }
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

            #expect(
                !(ctx.diagnostics.hasError),
                "Expected regular call program to compile without errors."
            )

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "callGreet", in: module, interner: ctx.interner)
            let flags = extractSuperCallFlags(from: body, interner: ctx.interner)

            let greetCall = flags.first { $0.callee == "greet" }
            #expect(greetCall != nil, "Expected a call to 'greet' in callGreet() body.")
            #expect(
                !(greetCall?.isSuperCall ?? true),
                "Expected this.greet() to have isSuperCall=false, got: \(flags)"
            )

            let dumpOutput = module.dump(interner: ctx.interner, symbols: ctx.sema?.symbols)
            #expect(
                !(dumpOutput.contains("super=1")),
                "Regular call dump should not contain 'super=1', got:\n\(dumpOutput)"
            )
        }
    }

    // MARK: - isSuperCall through lowering pipeline

    @Test func testIsSuperCallSurvivesLowering() throws {
        let sources: [String] = [
            """
            open class Base {
                open fun greet(): String = "hello"
            }
            class Child : Base() {
                override fun greet(): String = super.greet()
            }
            """,
            """
            open class Base2 {
                open fun process(x: Any): Any = x
            }
            class Child2 : Base2() {
                override fun process(x: Any): Any = super.process(x)
            }
            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths, emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)

            #expect(
                !(ctx.diagnostics.hasError),
                "Expected super call programs to compile and lower without errors, got: \(ctx.diagnostics.diagnostics.map(\.message))"
            )

            let module = try #require(ctx.kir)

            do {
                let flags = extractSuperCallFlagsAcrossOverrides(named: "greet", in: module, interner: ctx.interner)
                let superGreetCall = flags.first { $0.callee == "greet" && $0.isSuperCall }
                #expect(
                    superGreetCall != nil,
                    "Expected isSuperCall=true to survive full lowering pipeline, got: \(flags)"
                )
            }

            do {
                let flags = extractSuperCallFlagsAcrossOverrides(named: "process", in: module, interner: ctx.interner)
                let processCall = flags.first { $0.callee == "process" && $0.isSuperCall }
                #expect(
                    processCall != nil,
                    "Expected isSuperCall=true to survive ABI lowering with boxing, got: \(flags)"
                )
            }
        }
    }

    // MARK: - Qualified this@Label

    @Test func testQualifiedThisSema() throws {
        let sources: [String] = [
            """
            class Outer {
                fun getOuter(): Outer = this
                inner class Inner {
                    fun getOuter(): Outer = this@Outer
                }
            }
            """,
            """
            class Outer2 {
                class Inner {
                    fun bad(): Int = this@NonExistent
                }
            }
            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths, emit: .kirDump)
            try runSema(ctx)

            do {
                let sampleDiags = diagnosticsForPath(paths[0], in: ctx)
                let hasError = sampleDiags.contains { $0.severity == .error }
                #expect(
                    !(hasError),
                    "Expected this@Outer in nested class to resolve without errors, got: \(sampleDiags.map(\.message))"
                )
            }

            do {
                let sampleDiags = diagnosticsForPath(paths[1], in: ctx)
                assertHasDiagnostic("KSWIFTK-SEMA-0053", in: sampleDiags)
            }
        }
    }
}
#endif
