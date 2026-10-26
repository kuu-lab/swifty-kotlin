@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct InferredCompanionReturnTypeTests {
    @Test
    func inferredClassAndInterfaceCompanionsKeepTheirTypeAndInitialization() throws {
        let source = """
        var classCompanionInitialized = false
        var interfaceCompanionInitialized = false

        class Target {
            companion object {
                init { classCompanionInitialized = true }
                const val value = 42
            }
        }

        interface Source {
            companion object {
                init { interfaceCompanionInitialized = true }
                const val value = 24
            }
        }

        fun classCompanion() = Target
        fun interfaceCompanion() = Source
        fun readClass(): Int = classCompanion().value
        fun readInterface(): Int = interfaceCompanion().value
        fun directClass(): Int = Target.value
        fun explicitClass(): Target.Companion = Target
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runToKIR(ctx)
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(errors.isEmpty, "Got: \(errors)")

            let sema = try #require(ctx.sema)
            let interner = ctx.interner
            for (ownerName, functionName) in [
                ("Target", "classCompanion"),
                ("Source", "interfaceCompanion"),
            ] {
                let owner = try #require(sema.symbols.lookup(fqName: [interner.intern(ownerName)]))
                let companion = try #require(sema.symbols.companionObjectSymbol(for: owner))
                let companionType = sema.types.make(.classType(ClassType(
                    classSymbol: companion,
                    args: [],
                    nullability: .nonNull
                )))
                let function = try #require(sema.symbols.lookup(fqName: [interner.intern(functionName)]))
                #expect(sema.symbols.functionSignature(for: function)?.returnType == companionType)
            }
            for functionName in ["readClass", "readInterface", "directClass"] {
                let function = try #require(sema.symbols.lookup(fqName: [interner.intern(functionName)]))
                #expect(sema.symbols.functionSignature(for: function)?.returnType == sema.types.intType)
            }

            let module = try #require(ctx.kir)
            for (ownerName, functionName) in [
                ("Target", "classCompanion"),
                ("Source", "interfaceCompanion"),
            ] {
                let owner = try #require(sema.symbols.lookup(fqName: [interner.intern(ownerName)]))
                let companion = try #require(sema.symbols.companionObjectSymbol(for: owner))
                let initializerName = "__companion_lazy_init_\(companion.rawValue)"
                let body = try findKIRFunctionBody(named: functionName, in: module, interner: interner)
                #expect(body.contains { instruction in
                    guard case let .call(_, callee, _, _, _, _, _, _) = instruction else { return false }
                    return interner.resolve(callee) == initializerName
                })
            }

            let directBody = try findKIRFunctionBody(named: "directClass", in: module, interner: interner)
            let target = try #require(sema.symbols.lookup(fqName: [interner.intern("Target")]))
            let classCompanion = try #require(sema.symbols.companionObjectSymbol(for: target))
            #expect(!directBody.contains { instruction in
                guard case let .call(_, callee, _, _, _, _, _, _) = instruction else { return false }
                return interner.resolve(callee) == "__companion_lazy_init_\(classCompanion.rawValue)"
            })

            let explicit = try #require(sema.symbols.lookup(fqName: [interner.intern("explicitClass")]))
            let inferred = try #require(sema.symbols.lookup(fqName: [interner.intern("classCompanion")]))
            #expect(sema.symbols.functionSignature(for: explicit)?.returnType ==
                sema.symbols.functionSignature(for: inferred)?.returnType)
        }
    }
}
