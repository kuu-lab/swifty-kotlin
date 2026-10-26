#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct GenericCallCommonIntersectionInferenceTests {
    @Test
    func upstreamNonGenericIntersectionDelegationIsAccepted() throws {
        try assertGenericCallInfersIntersection(
            fixture: "delegationToIntersectionType.kt",
            functionName: "select",
            expectedParts: ["A", "B"]
        )
    }

    @Test
    func upstreamGenericIntersectionDelegationIsAccepted() throws {
        try assertGenericCallInfersIntersection(
            fixture: "delegationToIntersectionType3.kt",
            functionName: "select",
            expectedParts: ["A", "BBB"]
        )
    }

    @Test
    func inferredIntersectionSupportsDelegationAndItsControls() throws {
        let fixture = try runFixture("genericCallCommonIntersection.kt")
        let errors = fixtureErrors(fixture)
        #expect(errors.isEmpty, "Unexpected fixture diagnostics: \(diagnosticSummaries(errors))")

        let context = fixture.context
        let ast = try #require(context.ast)
        let sema = try #require(context.sema)
        let chooseCalls = ast.arena.exprs.indices.compactMap { index -> TypeID? in
            let exprID = ExprID(rawValue: Int32(index))
            guard let range = ast.arena.exprRange(exprID),
                  context.sourceManager.path(of: range.start.file) == fixture.path,
                  let binding = sema.bindings.callBinding(for: exprID),
                  let function = sema.symbols.symbol(binding.chosenCallee),
                  context.interner.resolve(function.name) == "choose"
            else {
                return nil
            }
            return binding.substitutedTypeArguments.first
        }
        #expect(chooseCalls.count == 3)

        let intersections = chooseCalls.filter {
            if case .intersection = sema.types.kind(of: $0) { return true }
            return false
        }
        #expect(intersections.count == 2)
        for inferred in intersections {
            #expect(try intersectionPartNames(inferred, in: context) == ["Marker", "Render"])
        }

        let explicitArguments = chooseCalls.filter {
            guard case let .classType(classType) = sema.types.kind(of: $0),
                  let symbol = sema.symbols.symbol(classType.classSymbol)
            else {
                return false
            }
            return context.interner.resolve(symbol.name) == "Render"
        }
        #expect(explicitArguments.count == 1)
    }

    @Test
    func incompatibleGenericIntersectionBoundIsRejected() throws {
        let fixture = try runFixture("incompatibleGenericIntersectionBounds.kt")
        let errors = fixtureErrors(fixture)
        #expect(!errors.isEmpty, "Expected incompatible Container arguments to be rejected")
        #expect(
            errors.contains { ["KSWIFTK-SEMA-0002", "KSWIFTK-TYPE-0001"].contains($0.code) },
            "Unexpected fixture diagnostics: \(diagnosticSummaries(errors))"
        )
    }

    private func assertGenericCallInfersIntersection(
        fixture: String,
        functionName: String,
        expectedParts: Set<String>
    ) throws {
        let loaded = try runFixture(fixture)
        let errors = fixtureErrors(loaded)
        #expect(errors.isEmpty, "Unexpected fixture diagnostics: \(diagnosticSummaries(errors))")
        let context = loaded.context
        let ast = try #require(context.ast)
        let sema = try #require(context.sema)
        let inferredArguments = ast.arena.exprs.indices.compactMap { index -> TypeID? in
            let exprID = ExprID(rawValue: Int32(index))
            guard let range = ast.arena.exprRange(exprID),
                  context.sourceManager.path(of: range.start.file) == loaded.path,
                  let binding = sema.bindings.callBinding(for: exprID),
                  let function = sema.symbols.symbol(binding.chosenCallee),
                  context.interner.resolve(function.name) == functionName
            else {
                return nil
            }
            return binding.substitutedTypeArguments.first
        }
        #expect(inferredArguments.count == 1)
        guard let inferred = inferredArguments.first else { return }
        #expect(try intersectionPartNames(inferred, in: context) == expectedParts)
    }

    private struct LoadedFixture {
        let context: CompilationContext
        let path: String
    }

    private func runFixture(_ name: String) throws -> LoadedFixture {
        let source = try repositoryFileSource("Tests/CompilerCoreTests/Fixtures/KUU-2210/\(name)")
        var context: CompilationContext?
        var inputPath: String?
        try withTemporaryFile(contents: source) { path in
            inputPath = path
            let compilationContext = makeCompilationContext(inputs: [path])
            try runSema(compilationContext)
            context = compilationContext
        }
        return LoadedFixture(context: try #require(context), path: try #require(inputPath))
    }

    private func fixtureErrors(_ fixture: LoadedFixture) -> [Diagnostic] {
        fixture.context.diagnostics.diagnostics.filter { diagnostic in
            guard diagnostic.severity == .error,
                  let range = diagnostic.primaryRange
            else {
                return false
            }
            return fixture.context.sourceManager.path(of: range.start.file) == fixture.path
        }
    }

    private func diagnosticSummaries(_ diagnostics: [Diagnostic]) -> [String] {
        diagnostics.map { "\($0.code): \($0.message)" }
    }

    private func intersectionPartNames(_ type: TypeID, in context: CompilationContext) throws -> Set<String> {
        let sema = try #require(context.sema)
        guard case let .intersection(parts) = sema.types.kind(of: type) else { return [] }
        return Set(parts.compactMap { part in
            guard case let .classType(classType) = sema.types.kind(of: part),
                  let symbol = sema.symbols.symbol(classType.classSymbol)
            else {
                return nil
            }
            return context.interner.resolve(symbol.name)
        })
    }
}
#endif
