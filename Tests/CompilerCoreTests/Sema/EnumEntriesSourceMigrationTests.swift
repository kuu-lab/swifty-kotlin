#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct EnumEntriesSourceMigrationTests {
    private static let fixture = SemaFixture(surface: "source-backed enum entries")

    @Test func remainingBundledEnumsExposeSourceBackedEntries() throws {
        let (sema, interner) = try Self.fixture.shared()
        let enumEntries = try #require(sema.symbols.lookup(fqName: [
            interner.intern("kotlin"), interner.intern("enums"), interner.intern("EnumEntries"),
        ]))
        let enumNames: [([String], [String])] = [
            (["kotlin", "annotation"], ["AnnotationRetention"]),
            (["kotlin", "annotation"], ["AnnotationTarget"]),
            (["kotlin", "time"], ["DurationUnit"]),
            (["kotlin", "text"], ["RegexOption"]),
            (["kotlin", "text"], ["CharCategory"]),
            (["kotlin"], ["DeprecationLevel"]),
            (["kotlin"], ["LazyThreadSafetyMode"]),
            (["kotlin", "io", "encoding"], ["Base64", "PaddingOption"]),
            (["kotlin", "native", "concurrent"], ["FutureState"]),
            (["kotlin", "native", "concurrent"], ["TransferMode"]),
        ]

        for (package, typeName) in enumNames {
            let name = package + typeName
            let fqName = name.map(interner.intern)
            let enumSymbol = try #require(sema.symbols.lookup(fqName: fqName), "Missing enum \(name)")
            let enumType = sema.types.make(.classType(ClassType(
                classSymbol: enumSymbol, args: [], nullability: .nonNull
            )))
            let propertyName = package.map(interner.intern) + [interner.intern("entries")]
            let property = try #require(sema.symbols.lookupAll(fqName: propertyName).first { symbol in
                sema.symbols.symbol(symbol)?.kind == .property
                    && sema.symbols.extensionPropertyReceiverType(for: symbol) == enumType
            }, "Missing source entries extension for \(name)")
            #expect(sema.symbols.isSourceBackedSymbol(property), "\(name) entries must have Kotlin source")
            #expect(sema.symbols.externalLinkName(for: property) == nil)
            let propertyType = try #require(sema.symbols.propertyType(for: property))
            guard case let .classType(classType) = sema.types.kind(of: propertyType) else {
                Issue.record("\(name) entries must have EnumEntries<T> type")
                continue
            }
            #expect(classType.classSymbol == enumEntries)
            let getter = try #require(sema.symbols.extensionPropertyGetterAccessor(for: property))
            #expect(sema.symbols.isSourceBackedSymbol(getter))
            #expect(sema.symbols.externalLinkName(for: getter) == nil)
        }
    }
}
#endif
