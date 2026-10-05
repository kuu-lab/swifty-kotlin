@testable import CompilerCore
import Testing
import TestStdlibCache

@Suite
struct MutableMapMemberSourceContractTests {
    @Test(arguments: [false, true])
    func allSevenMembersHaveCanonicalSourceOwnership(useArtifact: Bool) throws {
        if useArtifact { TestStdlibCache.shared.prepare() }
        try withTemporaryFiles(contents: ["""
        fun probe(map: MutableMap<String, Int>, from: Map<out String, Int>) {
            val entries: MutableSet<MutableMap.MutableEntry<String, Int>> = map.entries
            val keys: MutableSet<String> = map.keys
            val values: MutableCollection<Int> = map.values
            val previous: Int? = map.put("key", 1)
            map.putAll(from = from)
            val removed: Int? = map.remove("key")
            map.clear()
        }
        """]) { paths in
            let ctx = makeCompilationContext(
                inputs: paths,
                emit: useArtifact ? .executable : .kirDump,
                allowDefaultStdlibLibrary: useArtifact
            )
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            let sema = try #require(ctx.sema)
            let ownerName = ["kotlin", "collections", "MutableMap"].map(ctx.interner.intern)
            let owner = try #require(sema.symbols.lookup(fqName: ownerName))
            for name in ["entries", "keys", "values", "put", "putAll", "remove", "clear"] {
                let members = sema.symbols.lookupAll(fqName: ownerName + [ctx.interner.intern(name)]).filter {
                    sema.symbols.parentSymbol(for: $0) == owner
                }
                #expect(members.count == 1, "Duplicate MutableMap.\(name)")
                let member = try #require(members.first)
                #expect(sema.symbols.isSourceBackedSymbol(member))
                let link = switch name {
                case "entries", "keys", "values": "__kk_map_\(name)"
                default: "__kk_mutable_map_\(name)"
                }
                #expect(sema.symbols.externalLinkName(for: member) == link)
                #expect(sema.symbols.symbol(member)?.flags.contains(.importedLibrary) == useArtifact)
                if !useArtifact {
                    #expect(sema.symbols.symbol(member)?.flags.contains(.synthetic) == false)
                    let file = try #require(sema.symbols.sourceFileID(for: member))
                    #expect(ctx.sourceManager.path(of: file) == "__bundled_kotlin/collections/MutableMap.kt")
                }
            }
            let ast = try #require(ctx.ast)
            var calls = Set<String>()
            for (index, expr) in ast.arena.exprs.enumerated() {
                let id = ExprID(rawValue: Int32(index))
                guard let range = ast.arena.exprRange(id),
                      !ctx.sourceManager.path(of: range.start.file).hasPrefix("__bundled_"),
                      case let .memberCall(_, name, _, _, _) = expr,
                      ["put", "putAll", "remove", "clear"].contains(ctx.interner.resolve(name)),
                      let binding = sema.bindings.callBinding(for: id)
                else { continue }
                #expect(sema.symbols.parentSymbol(for: binding.chosenCallee) == owner)
                #expect(sema.symbols.isSourceBackedSymbol(binding.chosenCallee))
                calls.insert(ctx.interner.resolve(name))
            }
            #expect(calls == Set(["put", "putAll", "remove", "clear"]))
        }
    }

    @Test(arguments: [false, true])
    func putAllAcceptsCustomMapAndPreservesGenericSuperDispatch(useArtifact: Bool) throws {
        if useArtifact { TestStdlibCache.shared.prepare() }
        try withTemporaryFiles(contents: ["""
        class Input : AbstractMap<String, Int>() {
            override val entries: Set<Map.Entry<String, Int>> get() = emptySet()
        }
        abstract class Target : AbstractMutableMap<String, Int>() {
            override fun putAll(from: Map<out String, Int>) { super.putAll(from) }
        }
        fun probe(map: MutableMap<Any, Int>, target: Target) {
            map.putAll(Input())
            target.putAll(Input())
        }
        """]) { paths in
            let ctx = makeCompilationContext(
                inputs: paths,
                emit: useArtifact ? .executable : .kirDump,
                allowDefaultStdlibLibrary: useArtifact
            )
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            let sema = try #require(ctx.sema)
            let ast = try #require(ctx.ast)
            var owners = Set<String>()
            for (index, expr) in ast.arena.exprs.enumerated() {
                let id = ExprID(rawValue: Int32(index))
                guard let range = ast.arena.exprRange(id),
                      !ctx.sourceManager.path(of: range.start.file).hasPrefix("__bundled_"),
                      case let .memberCall(_, name, _, _, _) = expr,
                      ctx.interner.resolve(name) == "putAll",
                      let binding = sema.bindings.callBinding(for: id),
                      let owner = sema.symbols.parentSymbol(for: binding.chosenCallee),
                      let symbol = sema.symbols.symbol(owner)
                else { continue }
                owners.insert(symbol.fqName.map(ctx.interner.resolve).joined(separator: "."))
            }
            #expect(owners == Set(["kotlin.collections.MutableMap", "kotlin.collections.AbstractMutableMap", "Target"]))
        }
    }
}
