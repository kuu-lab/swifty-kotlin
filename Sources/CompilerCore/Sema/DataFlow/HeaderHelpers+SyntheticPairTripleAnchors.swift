
/// KSP-608: nominal anchors for `kotlin.Pair` / `kotlin.Triple`.
///
/// Both classes are declared in bundled Kotlin source (`kotlin/Tuples.kt`), so
/// they carry no synthetic members. Their *class symbols*, however, are needed
/// well before source headers are collected: a dozen synthetic collection,
/// sequence and string stubs (`Map.toList`, `String.zip`, `partition`, ...)
/// spell `Pair<K, V>` in their signatures and look the class up by name while
/// registering. Without an anchor those stubs silently degrade -- their return
/// type collapses to `Any`, or the whole stub is skipped and its call sites
/// type as `<error>`.
///
/// The anchor is deliberately member-less and arity-less: `collectHeader`
/// reuses a synthetic class symbol of the same fully-qualified name when it
/// reaches the real declaration (`reusableSyntheticDeclarationSymbol`) and
/// clears the `.synthetic` flag, so the source declaration -- or, when
/// compiling against a stdlib artifact, the imported metadata -- remains the
/// single source of truth for type parameters and members.
extension DataFlowSemaPhase {

    func registerSyntheticTupleNominalAnchors(
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let kotlinPkg = interner.intern("kotlin")
        for name in ["Pair", "Triple"] {
            let className = interner.intern(name)
            let fqName = [kotlinPkg, className]
            guard symbols.lookup(fqName: fqName) == nil else { continue }
            _ = symbols.define(
                kind: .class,
                name: className,
                fqName: fqName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
    }
}
