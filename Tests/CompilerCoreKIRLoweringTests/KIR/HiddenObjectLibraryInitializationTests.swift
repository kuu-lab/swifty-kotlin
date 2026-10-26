@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct HiddenObjectLibraryInitializationTests {
    private func libraryKIR(visibility: String) throws -> (CompilationContext, [KIRFunction]) {
        let base = makeContextFromSources([
            """
            package privateinit
            \(visibility)object Hidden
            fun hiddenValue(): Any = Hidden
            """,
        ])
        var options = base.options
        options.emit = .library
        let ctx = CompilationContext(options: options, sourceManager: base.sourceManager,
                                     diagnostics: base.diagnostics, interner: base.interner)
        try runToLowering(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let module = try #require(ctx.kir)
        let functions = module.arena.declarations.compactMap { declaration -> KIRFunction? in
            guard case let .function(function) = declaration else { return nil }
            return function
        }
        return (ctx, functions)
    }

    private func callees(of function: KIRFunction, in ctx: CompilationContext) -> [String] {
        function.body.compactMap { instruction in
            if case let .call(_, callee, _, _, _, _, _, _) = instruction { return ctx.interner.resolve(callee) }
            return nil
        }
    }

    @Test
    func privateObjectEagerInitRunsFromLibraryEntryPoint() throws {
        let (ctx, functions) = try libraryKIR(visibility: "private ")
        let libraryInit = try #require(functions.first {
            ctx.interner.resolve($0.name).hasPrefix("__kk_library_top_level_init_")
        })
        #expect(callees(of: libraryInit, in: ctx).contains { $0.hasPrefix("__object_init_") })
    }

    @Test
    func objectEagerInitRegistersClassMetadata() throws {
        let (ctx, functions) = try libraryKIR(visibility: "private ")
        let objectInit = try #require(functions.first {
            ctx.interner.resolve($0.name).hasPrefix("__object_init_")
        })
        #expect(callees(of: objectInit, in: ctx).contains("__kk_kclass_register_metadata"))
    }
}
