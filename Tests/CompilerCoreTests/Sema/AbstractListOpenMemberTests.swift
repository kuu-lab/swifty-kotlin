#if canImport(Testing)
@testable import CompilerCore
import Testing
import TestStdlibCache

@Suite
struct AbstractListOpenMemberTests {
    @Test(arguments: [false, true])
    func canonicalMembersAndOverrideBindings(useLibrary: Bool) throws {
        if useLibrary { TestStdlibCache.shared.prepare() }
        let source = """
        class OpenList : AbstractList<Int>() {
            override val size: Int get() = 1
            override fun get(index: Int): Int = 7
            override fun indexOf(element: Int): Int = 101
            override fun lastIndexOf(element: Int): Int = 202
            override fun subList(fromIndex: Int, toIndex: Int): List<Int> = listOf(303)
        }
        fun probe(abstract: AbstractList<Int>, list: List<Int>) {
            abstract.indexOf(7)
            abstract.lastIndexOf(7)
            abstract.subList(0, 1)
            list.indexOf(7)
            list.lastIndexOf(7)
            list.subList(0, 1)
        }
        fun <L : List<Int>> boundedProbe(list: L) {
            list.indexOf(7)
            list.lastIndexOf(7)
            list.subList(0, 1)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let libraryPath = useLibrary ? CompilerOptions.defaultStdlibLibraryPath : nil
            let ctx = makeCompilationContext(inputs: [path], stdlibLibraryPath: libraryPath)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            let sema = try #require(ctx.sema)
            let ast = try #require(ctx.ast)
            let fqName = ["kotlin", "collections", "AbstractList"].map(ctx.interner.intern)
            let owner = try #require(sema.symbols.lookup(fqName: fqName))
            let listFQName = ["kotlin", "collections", "List"].map(ctx.interner.intern)
            let listOwner = try #require(sema.symbols.lookup(fqName: listFQName))
            let listLayout = try #require(sema.symbols.nominalLayout(for: listOwner))
            for (name, arity, slot) in [("get", 1, 0), ("listIterator", 1, 1), ("subList", 2, 2)] {
                let member = try #require(sema.symbols.lookupAll(fqName: listFQName + [ctx.interner.intern(name)]).first {
                    sema.symbols.parentSymbol(for: $0) == listOwner
                        && sema.symbols.symbol($0)?.flags.contains(.extensionMemberAlias) == false
                        && sema.symbols.functionSignature(for: $0)?.parameterTypes.count == arity
                })
                #expect(listLayout.vtableSlots[member] == slot)
            }
            for name in ["indexOf", "lastIndexOf", "subList"] {
                let members = sema.symbols.lookupAll(fqName: fqName + [ctx.interner.intern(name)]).filter {
                    sema.symbols.parentSymbol(for: $0) == owner
                        && sema.symbols.symbol($0)?.kind == .function
                        && sema.symbols.symbol($0)?.flags.contains(.extensionMemberAlias) == false
                }
                #expect(members.count == 1)
                let member = try #require(members.first)
                let info = try #require(sema.symbols.symbol(member))
                #expect(info.flags.contains(.overrideMember))
                #expect(!info.flags.contains(.finalMember))
                if !useLibrary {
                    #expect(sema.symbols.externalLinkName(for: member) == nil)
                    #expect(sema.symbols.isSourceBackedSymbol(member))
                    let file = try #require(sema.symbols.sourceFileID(for: member))
                    #expect(ctx.sourceManager.path(of: file) == "__bundled_kotlin/collections/AbstractList.kt")
                } else {
                    #expect(sema.symbols.externalLinkName(for: member)?.hasPrefix("kk_fn_\(name)_") == true)
                }
            }
            var calls = 0
            for index in ast.arena.exprs.indices {
                let exprID = ExprID(rawValue: Int32(index))
                guard let range = ast.arena.exprRange(exprID),
                      ctx.sourceManager.path(of: range.start.file) == path,
                      case let .memberCall(_, name, _, _, _) = ast.arena.expr(exprID),
                      ["indexOf", "lastIndexOf", "subList"].contains(ctx.interner.resolve(name))
                else { continue }
                let callee = try #require(sema.bindings.callBinding(for: exprID)?.chosenCallee)
                let parent = try #require(sema.symbols.parentSymbol(for: callee))
                let parentName = try #require(sema.symbols.symbol(parent)).fqName.map(ctx.interner.resolve).joined(separator: ".")
                #expect(["kotlin.collections.AbstractList", "kotlin.collections.List"].contains(parentName), "\(ctx.interner.resolve(name)): \(parentName)")
                #expect(sema.symbols.symbol(callee)?.flags.contains(.extensionMemberAlias) == false)
                calls += 1
            }
            #expect(calls == 9)
        }
    }
}
#endif
