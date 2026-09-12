#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// KSP-699: the `kotlin.collections` factory functions are source-backed
/// declarations with no bootstrap synthetic stub
/// (`HeaderHelpers+SyntheticCollectionFactoryStubs.swift` is deleted).
///
/// `CollectionLiteralLoweringTests` covers the same names, but it hand-builds
/// `.call(symbol: nil, ...)` KIR against a `KIRContext` without a `SemaModule`.
/// That short-circuits `isStdlibCollectionFactory` at its
/// `guard let sym … else { return true }`, so those cases exercise the
/// name-only fallback rather than the path a real Kotlin input takes. The
/// tests below drive the compiler from source instead, which is how the
/// `arrayListOf` / `mutableListOf` runtime-tag divergence below stayed hidden:
/// `CallLowerer` emitted `__kk_list_of` while the fallback emitted
/// `__kk_array_list_of`.
@Suite
struct CollectionFactorySourceMigrationTests {
    /// Every name the deleted bootstrap stub used to register, paired with the
    /// bundled file that now declares it.
    private static let factoryOwners: [String: String] = [
        "emptyList": "CollectionFactories.kt",
        "listOf": "CollectionFactories.kt",
        "mutableListOf": "CollectionFactories.kt",
        "arrayListOf": "CollectionFactories.kt",
        "listOfNotNull": "CollectionFactories.kt",
        "emptySet": "CollectionFactories.kt",
        "setOf": "CollectionFactories.kt",
        "setOfNotNull": "CollectionFactories.kt",
        "mutableSetOf": "CollectionFactories.kt",
        "emptyMap": "CollectionFactories.kt",
        "mapOf": "CollectionFactories.kt",
        "mutableMapOf": "CollectionFactories.kt",
        "hashSetOf": "hash.kt",
        "hashMapOf": "hash.kt",
        "linkedSetOf": "linked.kt",
        "linkedMapOf": "linked.kt",
    ]

    private static let factorySource = """
    fun main() {
        val a = emptyList<Int>()
        val b = listOf(1, 2)
        val c = mutableListOf(1, 2)
        val d = arrayListOf(1, 2)
        val e = listOfNotNull(1, null)
        val f = emptySet<Int>()
        val g = setOf(1, 2)
        val h = setOfNotNull(1, null)
        val i = mutableSetOf(1, 2)
        val j = hashSetOf(1, 2)
        val k = linkedSetOf(1, 2)
        val l = emptyMap<String, Int>()
        val m = mapOf("a" to 1)
        val n = mutableMapOf("a" to 1)
        val o = hashMapOf("a" to 1)
        val p = linkedMapOf("a" to 1)
    }
    """

    /// The `kotlin.collections` package FQName prefix, interned in `ctx`.
    private static func collectionsPackage(_ ctx: CompilationContext) -> [InternedString] {
        ["kotlin", "collections"].map(ctx.interner.intern)
    }

    // MARK: - declaration surface

    /// No factory name may keep a synthetic overload alongside the bundled
    /// stdlib: overload resolution could otherwise pick the stub, whose return
    /// type was `Any`, over the Kotlin declaration.
    @Test
    func factoryNamesHaveNoSyntheticOverload() throws {
        try withTemporaryFile(contents: Self.factorySource) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "CollectionFactoryDeclarations",
                emit: .kirDump
            )
            try runToKIR(ctx)
            #expect(!ctx.diagnostics.hasError, "diagnostics: \(ctx.diagnostics.diagnostics)")

            let sema = try #require(ctx.sema)
            let packageFQName = Self.collectionsPackage(ctx)
            for name in Self.factoryOwners.keys.sorted() {
                let overloads = sema.symbols.lookupAll(fqName: packageFQName + [ctx.interner.intern(name)])
                #expect(!overloads.isEmpty, "\(name) must be declared by the bundled stdlib")

                let synthetic = overloads.filter { sema.symbols.symbol($0)?.flags.contains(.synthetic) == true }
                #expect(
                    synthetic.isEmpty,
                    "\(name) must have no synthetic overload alongside the bundled stdlib"
                )
            }
        }
    }

    /// Each factory resolves into the bundled file that declares it, so the
    /// declaration the call site binds to really is Kotlin source.
    @Test
    func factoryCallsResolveIntoTheirBundledSourceFile() throws {
        try withTemporaryFile(contents: Self.factorySource) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "CollectionFactoryOwners",
                emit: .kirDump
            )
            try runToKIR(ctx)
            #expect(!ctx.diagnostics.hasError, "diagnostics: \(ctx.diagnostics.diagnostics)")

            let sema = try #require(ctx.sema)
            let packageFQName = Self.collectionsPackage(ctx)
            for (name, expectedFile) in Self.factoryOwners.sorted(by: { $0.key < $1.key }) {
                let overloads = sema.symbols.lookupAll(fqName: packageFQName + [ctx.interner.intern(name)])
                let files: Set<String> = Set(overloads.compactMap { symbolID in
                    guard let fileID = sema.symbols.sourceFileID(for: symbolID) else { return nil }
                    return ctx.sourceManager.path(of: fileID)
                })
                #expect(
                    files.contains("__bundled_kotlin/collections/\(expectedFile)"),
                    "\(name) must be declared by \(expectedFile); resolved files: \(files.sorted())"
                )
            }
        }
    }

    /// Without the bundled stdlib nothing declares the factories any more, so
    /// no production input can reach the lowering path through a stub.
    @Test
    func noStdlibHasNoCollectionFactoryEntryPoint() throws {
        let source = """
        fun main() {
            val a = arrayListOf(1, 2)
            val b = listOf(1, 2)
            val c = mutableSetOf(1)
            val d = hashMapOf("a" to 1)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "CollectionFactoryNoStdlib",
                emit: .kirDump,
                includeStdlib: false
            )
            try runToKIR(ctx)

            let unresolved = ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-0023" }
            for name in ["arrayListOf", "listOf", "mutableSetOf", "hashMapOf"] {
                #expect(
                    unresolved.contains { $0.message.contains("'\(name)'") },
                    "\(name) must be unresolved without stdlib; diagnostics: \(ctx.diagnostics.diagnostics)"
                )
            }

            let sema = try #require(ctx.sema)
            #expect(
                sema.symbols.lookup(fqName: Self.collectionsPackage(ctx) + [ctx.interner.intern("arrayListOf")]) == nil
            )
        }
    }

    // MARK: - production runtime routing

    /// `arrayListOf` / `mutableListOf` declare a mutable result, so their box
    /// must carry the `ArrayList` runtime tag. `__kk_list_of` tags the
    /// read-only `List`, which makes `is MutableList` / `is ArrayList` answer
    /// false on the result (verified against kotlinc in
    /// `Scripts/diff_cases/ksp699_collection_factories.kt`).
    @Test
    func mutableListFactoriesUseTheArrayListTaggedBridge() throws {
        let source = """
        fun main() {
            val emptyArrayList = arrayListOf<Int>()
            val filledArrayList = arrayListOf(1, 2)
            val emptyMutable = mutableListOf<Int>()
            val filledMutable = mutableListOf(1, 2)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "CollectionFactoryMutableListTag",
                emit: .kirDump
            )
            try runToKIR(ctx)
            #expect(!ctx.diagnostics.hasError, "diagnostics: \(ctx.diagnostics.diagnostics)")

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)

            #expect(
                callees.filter { $0 == "__kk_array_list_of" }.count == 4,
                "all four mutable list factory calls must use __kk_array_list_of; callees: \(callees)"
            )
            #expect(
                !callees.contains("__kk_list_of"),
                "no mutable list factory may fall back to the read-only List tag; callees: \(callees)"
            )
        }
    }

    /// The read-only counterparts must keep the `List` tag, so the fix above
    /// does not hand them a mutable nominal identity.
    @Test
    func readOnlyListFactoriesKeepTheReadOnlyTag() throws {
        let source = """
        fun main() {
            val a = listOf(1, 2)
            val b = emptyList<Int>()
            val c = listOf<Int>()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "CollectionFactoryReadOnlyListTag",
                emit: .kirDump
            )
            try runToKIR(ctx)
            #expect(!ctx.diagnostics.hasError, "diagnostics: \(ctx.diagnostics.diagnostics)")

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)

            #expect(
                !callees.contains("__kk_array_list_of"),
                "read-only list factories must not take the ArrayList tag; callees: \(callees)"
            )
            #expect(
                callees.contains("__kk_emptyList") || callees.contains("__kk_list_of"),
                "read-only list factories must still reach a List-tagged bridge; callees: \(callees)"
            )
        }
    }

    /// The bootstrap stub set an `externalLinkName` on each factory symbol, so
    /// a leftover one would mean a stub is still being registered. The vararg
    /// overloads must also survive, since that is the shape the factory call
    /// sites bind to.
    @Test
    func factoryOverloadsKeepNoBootstrapLinkName() throws {
        let source = """
        fun main() {
            val a = arrayListOf(1, 2)
            val b = mutableListOf(1, 2)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "CollectionFactorySymbols",
                emit: .kirDump
            )
            try runToKIR(ctx)
            #expect(!ctx.diagnostics.hasError, "diagnostics: \(ctx.diagnostics.diagnostics)")

            let sema = try #require(ctx.sema)
            let packageFQName = Self.collectionsPackage(ctx)
            for name in ["arrayListOf", "mutableListOf"] {
                let overloads = sema.symbols.lookupAll(fqName: packageFQName + [ctx.interner.intern(name)])
                let varargOverloads = overloads.filter { symbolID in
                    sema.symbols.functionSignature(for: symbolID)?.valueParameterIsVararg.contains(true) == true
                }
                #expect(
                    !varargOverloads.isEmpty,
                    "\(name) must keep a vararg overload for the factory call sites"
                )
                for symbolID in overloads {
                    #expect(
                        sema.symbols.externalLinkName(for: symbolID) == nil,
                        "\(name) must not carry a bootstrap external link name"
                    )
                }
            }
        }
    }
}
#endif
