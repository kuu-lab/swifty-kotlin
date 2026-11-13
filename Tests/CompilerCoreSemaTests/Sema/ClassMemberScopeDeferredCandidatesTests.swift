#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// KUU-4574: `ClassMemberScope.deferredCandidates` memoizes its supertype-chain
/// walk per name and revalidates the visited parents' dependency versions, so
/// repeat lookups must not rescan children — and every mutation the walk can
/// observe (child reparenting, supertype edges, child visibility) must
/// invalidate the memo.
@Suite
struct ClassMemberScopeDeferredCandidatesTests {
    private struct Fixture {
        let interner: StringInterner
        let symbols: SymbolTable
        let owner: SymbolID
        let base: SymbolID
        let scope: ClassMemberScope
    }

    /// Owner `Sub` extends class `Base`; `Base` carries decoy members so a
    /// full child-set scan would do real work.
    private func makeFixture() -> Fixture {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let baseName = interner.intern("Base")
        let subName = interner.intern("Sub")
        let base = symbols.define(
            kind: .class, name: baseName, fqName: [baseName], declSite: nil, visibility: .public
        )
        let sub = symbols.define(
            kind: .class, name: subName, fqName: [subName], declSite: nil, visibility: .public
        )
        symbols.setDirectSupertypes([base], for: sub)
        for decoy in ["decoyFunction", "decoyProperty"] {
            let name = interner.intern(decoy)
            let kind: SymbolKind = decoy.hasSuffix("Function") ? .function : .property
            let member = symbols.define(
                kind: kind, name: name, fqName: [baseName, name], declSite: nil, visibility: .public
            )
            symbols.setParentSymbol(base, for: member)
        }
        let scope = ClassMemberScope(parent: nil, symbols: symbols, ownerSymbol: sub, thisType: nil)
        return Fixture(interner: interner, symbols: symbols, owner: sub, base: base, scope: scope)
    }

    private func addNestedClassifier(
        _ fixture: Fixture, name: String, kind: SymbolKind = .class, visibility: Visibility = .public,
        parent: SymbolID? = nil
    ) -> SymbolID {
        let parentSymbol = parent ?? fixture.base
        let nameID = fixture.interner.intern(name)
        guard let parentInfo = fixture.symbols.symbol(parentSymbol) else {
            preconditionFailure("fixture parent missing")
        }
        let symbol = fixture.symbols.define(
            kind: kind, name: nameID,
            fqName: parentInfo.fqName + [nameID],
            declSite: nil, visibility: visibility
        )
        fixture.symbols.setParentSymbol(parentSymbol, for: symbol)
        return symbol
    }

    @Test
    func repeatedLookupReusesMemoWithoutRescanning() {
        let fixture = makeFixture()
        let nested = addNestedClassifier(fixture, name: "Nested")
        fixture.symbols.attribution = TypeCheckAttribution()
        let name = fixture.interner.intern("Nested")

        let first = fixture.scope.deferredCandidates(for: name)
        #expect(first == [nested])
        let scannedAfterFirst = fixture.symbols.attribution?.value(.memberScopeCandidatesScanned) ?? -1
        #expect(scannedAfterFirst > 0)
        let queriesAfterFirst = fixture.symbols.attribution?.value(.memberScopeQueries) ?? -1

        let second = fixture.scope.deferredCandidates(for: name)
        #expect(second == [nested])
        #expect(fixture.symbols.attribution?.value(.memberScopeQueries) == queriesAfterFirst + 1)
        // The memoized repeat validates dependency versions instead of
        // scanning any child entries.
        #expect(
            fixture.symbols.attribution?.value(.memberScopeCandidatesScanned) == scannedAfterFirst
        )
    }

    @Test
    func newNestedClassifierOnVisitedSupertypeInvalidatesMemo() {
        let fixture = makeFixture()
        fixture.symbols.attribution = TypeCheckAttribution()
        let name = fixture.interner.intern("Target")

        #expect(fixture.scope.deferredCandidates(for: name).isEmpty)

        let added = addNestedClassifier(fixture, name: "Target")
        #expect(fixture.scope.deferredCandidates(for: name) == [added])
    }

    @Test
    func visibilityChangeOnInheritedCandidateInvalidatesMemo() {
        let fixture = makeFixture()
        let nested = addNestedClassifier(fixture, name: "Target")
        fixture.symbols.attribution = TypeCheckAttribution()
        let name = fixture.interner.intern("Target")

        #expect(fixture.scope.deferredCandidates(for: name) == [nested])

        // Private members are not inherited (KUU-3798): the memo must not
        // keep serving the public candidate after the visibility flip.
        fixture.symbols.setVisibility(.private, for: nested)
        #expect(fixture.scope.deferredCandidates(for: name).isEmpty)

        fixture.symbols.setVisibility(.public, for: nested)
        #expect(fixture.scope.deferredCandidates(for: name) == [nested])
    }

    @Test
    func ownPrivateNestedClassifierRemainsVisibleAcrossMemo() {
        let fixture = makeFixture()
        let nested = addNestedClassifier(
            fixture, name: "PrivateNested", visibility: .private, parent: fixture.owner
        )
        let name = fixture.interner.intern("PrivateNested")

        #expect(fixture.scope.deferredCandidates(for: name) == [nested])
        #expect(fixture.scope.deferredCandidates(for: name) == [nested])
    }

    @Test
    func supertypeEdgeChangeInvalidatesMemo() {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let ownerName = interner.intern("Root")
        let owner = symbols.define(
            kind: .class, name: ownerName, fqName: [ownerName], declSite: nil, visibility: .public
        )
        let baseName = interner.intern("AddedBase")
        let base = symbols.define(
            kind: .class, name: baseName, fqName: [baseName], declSite: nil, visibility: .public
        )
        let name = interner.intern("Target")
        let target = symbols.define(
            kind: .class, name: name, fqName: [baseName, name], declSite: nil, visibility: .public
        )
        symbols.setParentSymbol(base, for: target)
        let scope = ClassMemberScope(parent: nil, symbols: symbols, ownerSymbol: owner, thisType: nil)

        #expect(scope.deferredCandidates(for: name).isEmpty)

        symbols.setDirectSupertypes([base], for: owner)
        #expect(scope.deferredCandidates(for: name) == [target])
        // And the new answer memoizes for subsequent lookups.
        #expect(scope.deferredCandidates(for: name) == [target])
    }

    @Test
    func interfaceSupertypeEndsTheWalkAcrossMemo() {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let contractName = interner.intern("Contract")
        let contract = symbols.define(
            kind: .interface, name: contractName, fqName: [contractName], declSite: nil, visibility: .public
        )
        let entryName = interner.intern("Entry")
        let entry = symbols.define(
            kind: .class, name: entryName, fqName: [contractName, entryName], declSite: nil, visibility: .public
        )
        symbols.setParentSymbol(contract, for: entry)
        let childName = interner.intern("Child")
        let child = symbols.define(
            kind: .class, name: childName, fqName: [childName], declSite: nil, visibility: .public
        )
        symbols.setDirectSupertypes([contract], for: child)
        let scope = ClassMemberScope(parent: nil, symbols: symbols, ownerSymbol: child, thisType: nil)

        // KUU-3637: a nested classifier reachable only through an interface
        // supertype is not visible by simple name; the memo must preserve
        // that on repeat lookups.
        #expect(scope.deferredCandidates(for: entryName).isEmpty)
        #expect(scope.deferredCandidates(for: entryName).isEmpty)
    }

    @Test
    func childrenNamedMatchesChildrenOfFilter() {
        let fixture = makeFixture()
        let target = addNestedClassifier(fixture, name: "Target")
        addNestedClassifier(fixture, name: "Other")

        let all = fixture.symbols.children(of: fixture.base)
        let named = fixture.symbols.children(of: fixture.base, named: fixture.interner.intern("Target"))
        #expect(named == [target])
        #expect(named == all.filter { fixture.symbols.symbol($0)?.name == fixture.interner.intern("Target") })
    }

    @Test
    func reparentedCandidateInvalidatesMemo() {
        let fixture = makeFixture()
        let name = fixture.interner.intern("Target")
        let target = addNestedClassifier(fixture, name: "Target")

        #expect(fixture.scope.deferredCandidates(for: name) == [target])

        // Moving the candidate out of the chain must empty the memoized answer.
        let outsideName = fixture.interner.intern("Outside")
        let outside = fixture.symbols.define(
            kind: .class, name: outsideName, fqName: [outsideName], declSite: nil, visibility: .public
        )
        fixture.symbols.setParentSymbol(outside, for: target)
        #expect(fixture.scope.deferredCandidates(for: name).isEmpty)
    }
}
#endif
