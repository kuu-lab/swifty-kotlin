@testable import CompilerCore
import Testing

@Suite
struct TopLevelStartupIsolationTests {
    private func context(entry: String? = nil, emit: EmitMode = .kirDump) -> CompilationContext {
        let base = makeContextFromSources([
            """
            val seed = if (1 < 2) 7 else 9
            fun main() {}
            class Owner { fun main() {} }
            fun container() { fun main() {}; main() }
            """,
            """
            package helpers
            fun main() {}
            """,
        ])
        var options = base.options
        options.entryPointFQName = entry
        options.emit = emit
        return CompilationContext(options: options, sourceManager: base.sourceManager,
                                  diagnostics: base.diagnostics, interner: base.interner)
    }

    @Test(arguments: [nil, "helpers.main"] as [String?])
    func startupBelongsOnlyToSelectedFileLevelEntry(entry: String?) throws {
        let ctx = context(entry: entry)
        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let module = try #require(ctx.kir)
        let flags = sema.symbols.allSymbols().filter {
            ctx.interner.resolve($0.name) == "$startupInitialized"
        }
        let flag = try #require(flags.first)
        #expect(flags.count == 1)
        #expect(flag.visibility == .private && flag.flags == [.synthetic])
        let functions = module.arena.declarations.compactMap { declaration -> KIRFunction? in
            guard case let .function(function) = declaration else { return nil }
            return function
        }
        let initializedFunctions = functions.filter { function in
            function.body.contains { instruction in
                if case let .storeGlobal(_, symbol) = instruction { return symbol == flag.id }
                return false
            }
        }
        #expect(initializedFunctions.count == 1)
        let selected = try #require(initializedFunctions.first)
        #expect(sema.symbols.symbol(selected.symbol)?.fqName.map(ctx.interner.resolve).joined(separator: ".")
                == (entry ?? "main"))
        let labels = selected.body.compactMap { instruction -> Int32? in
            if case let .label(label) = instruction { return label }
            return nil
        }
        #expect(labels.count == Set(labels).count)
    }

    @Test
    func libraryMainIsAnOrdinaryFunction() throws {
        let ctx = context(emit: .library)
        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let module = try #require(ctx.kir)
        #expect(!sema.symbols.allSymbols().contains {
            ctx.interner.resolve($0.name) == "$startupInitialized"
        })
        let functions = module.arena.declarations.compactMap { declaration -> KIRFunction? in
            guard case let .function(function) = declaration else { return nil }
            return function
        }
        #expect(functions.contains {
            ctx.interner.resolve($0.name).hasPrefix("__kk_library_top_level_init_")
        })
        for function in functions where ctx.interner.resolve(function.name) == "main" {
            #expect(!function.body.contains { instruction in
                if case .storeGlobal = instruction { return true }
                return false
            })
        }
    }
}
