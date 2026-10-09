#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct ReceiverPredicateEquivalenceTests {
    private enum Predicate: Hashable {
        case regex
        case sequence
        case listLike
        case strictList
        case listCollection
        case concreteCollection
        case collectionAggregate
        case setLike
        case strictSet
        case mutableSetLike
        case strictMutableSet
        case arrayLike
        case concreteArrayLike
        case coroutineHandle
        case channel
    }

    private struct TypeCase {
        let name: String
        let type: TypeID
        let expected: Set<Predicate>
    }

    private struct Fixture {
        let interner: StringInterner
        let sema: SemaModule
        let callLowerer: CallLowerer
        let callChecker: CallTypeChecker
        private let typeCheckDriver: TypeCheckDriver
        private let kirDriver: KIRLoweringDriver
        private let sourceManager: SourceManager

        init() {
            let interner = StringInterner()
            let diagnostics = DiagnosticEngine()
            let symbols = SymbolTable()
            let types = TypeSystem()
            types.symbolTable = symbols
            let bindings = BindingTable()
            let sema = makeSemaModule(
                symbols: symbols,
                types: types,
                bindings: bindings,
                diagnostics: diagnostics
            ).ctx
            let ast = ASTModule(files: [], arena: ASTArena(), declarationCount: 0, tokenCount: 0)
            let typeCheckDriver = TypeCheckDriver(
                ast: ast,
                sema: sema,
                semaCtx: sema,
                solver: ConstraintSolver(),
                resolver: OverloadResolver(),
                dataFlow: DataFlowAnalyzer(),
                interner: interner,
                diagnostics: diagnostics
            )
            let kirDriver = KIRLoweringDriver(ctx: KIRLoweringContext())

            self.interner = interner
            self.sema = sema
            self.typeCheckDriver = typeCheckDriver
            self.kirDriver = kirDriver
            self.callLowerer = CallLowerer(driver: kirDriver)
            self.callChecker = CallTypeChecker(driver: typeCheckDriver)
            self.sourceManager = SourceManager()
        }

        func classType(
            _ components: [String],
            kind: SymbolKind = .interface,
            args: [TypeArg] = [],
            nullability: Nullability = .nonNull,
            flags: SymbolFlags = [],
            sourceBacked: Bool = false,
            fqName: [String]? = nil
        ) -> TypeID {
            var declSite: SourceRange?
            if sourceBacked {
                let name = components.last!
                let contents = Data("interface \(name)\n".utf8)
                let file = sourceManager.addFile(
                    path: "receiver-predicate-tests/\(name).kt",
                    contents: contents,
                    origin: .user
                )
                declSite = SourceRange(
                    start: SourceLocation(file: file, offset: 0),
                    end: SourceLocation(file: file, offset: contents.count)
                )
            }
            let symbol = sema.symbols.define(
                kind: kind,
                name: interner.intern(components.last!),
                fqName: (fqName ?? components).map(interner.intern),
                declSite: declSite,
                visibility: .public,
                flags: flags
            )
            return sema.types.make(.classType(ClassType(
                classSymbol: symbol,
                args: args,
                nullability: nullability
            )))
        }

        func retype(
            _ type: TypeID,
            args: [TypeArg],
            nullability: Nullability = .nonNull
        ) -> TypeID {
            guard let (classType, _) = resolveClassTypeSymbol(type, sema: sema) else {
                preconditionFailure("Expected class type")
            }
            return sema.types.make(.classType(ClassType(
                classSymbol: classType.classSymbol,
                args: args,
                nullability: nullability
            )))
        }
    }

    @Test
    func semaAndKIRAdaptersPreserveTheirDocumentedReceiverPredicates() {
        let fixture = Fixture()
        let string = fixture.sema.types.stringType
        let genericString: [TypeArg] = [.invariant(string)]

        // FQN source-backed types, nullable and generic types, unparameterized
        // receiver types, simple-name user classes, and synthetic no-FQN stubs
        // are compared through every legacy Sema/KIR adapter.
        let list = fixture.classType(
            ["kotlin", "collections", "List"],
            args: genericString,
            sourceBacked: true
        )
        let set = fixture.classType(["kotlin", "collections", "Set"], args: genericString)
        let mutableSet = fixture.classType(["kotlin", "collections", "MutableSet"], args: genericString)
        let sourceCases: [TypeCase] = [
            TypeCase(name: "source List<String>", type: list, expected: [
                .listLike, .strictList, .listCollection, .concreteCollection, .collectionAggregate,
            ]),
            TypeCase(
                name: "nullable List<String>",
                type: fixture.retype(list, args: genericString, nullability: .nullable),
                expected: [
                    .listLike, .strictList, .listCollection, .concreteCollection, .collectionAggregate,
                ]
            ),
            TypeCase(
                name: "raw List",
                type: fixture.retype(list, args: []),
                expected: [.listLike, .listCollection, .concreteCollection, .collectionAggregate]
            ),
            TypeCase(
                name: "List<*>",
                type: fixture.retype(list, args: [.star]),
                expected: [
                    .listLike, .strictList, .listCollection, .concreteCollection, .collectionAggregate,
                ]
            ),
            TypeCase(
                name: "Set<String>",
                type: set,
                expected: [.strictSet, .setLike, .concreteCollection, .collectionAggregate]
            ),
            TypeCase(
                name: "raw Set",
                type: fixture.retype(set, args: []),
                expected: [.setLike, .concreteCollection, .collectionAggregate]
            ),
            TypeCase(
                name: "MutableSet<String>",
                type: mutableSet,
                expected: [
                    .setLike, .strictSet, .mutableSetLike, .strictMutableSet,
                    .concreteCollection, .collectionAggregate,
                ]
            ),
            TypeCase(
                name: "raw MutableSet",
                type: fixture.retype(mutableSet, args: []),
                expected: [.setLike, .mutableSetLike, .concreteCollection, .collectionAggregate]
            ),
            TypeCase(
                name: "Array<String>",
                type: fixture.classType(["kotlin", "Array"], args: genericString),
                expected: [.arrayLike, .concreteArrayLike]
            ),
            TypeCase(
                name: "IntArray",
                type: fixture.classType(["kotlin", "IntArray"]),
                expected: [.arrayLike, .concreteArrayLike]
            ),
            TypeCase(
                name: "Sequence<String>",
                type: fixture.classType(["kotlin", "sequences", "Sequence"], args: genericString),
                expected: [.sequence, .concreteCollection, .collectionAggregate]
            ),
            TypeCase(
                name: "user List<String> (simple-name fallback)",
                type: fixture.classType(["com", "example", "List"], kind: .class, args: genericString),
                expected: [
                    .listLike, .strictList, .listCollection, .concreteCollection, .collectionAggregate,
                ]
            ),
            TypeCase(
                name: "user Set<String> (non-synthetic FQN)",
                type: fixture.classType(["com", "example", "Set"], kind: .class, args: genericString),
                expected: []
            ),
            TypeCase(
                name: "user MutableSet<String> (simple-name fallback)",
                type: fixture.classType(["com", "example", "MutableSet"], kind: .class, args: genericString),
                expected: [.mutableSetLike, .strictMutableSet]
            ),
            TypeCase(
                name: "synthetic Set<String> without FQN",
                type: fixture.classType(
                    ["Set"],
                    args: genericString,
                    flags: [.synthetic],
                    fqName: []
                ),
                expected: [.strictSet, .setLike, .concreteCollection, .collectionAggregate]
            ),
            TypeCase(
                name: "user Array<String> (simple-name fallback)",
                type: fixture.classType(["com", "example", "Array"], kind: .class, args: genericString),
                expected: [.arrayLike, .concreteArrayLike]
            ),
            TypeCase(
                name: "user Regex (simple-name fallback)",
                type: fixture.classType(["com", "example", "Regex"], kind: .class),
                expected: [.regex]
            ),
            TypeCase(
                name: "user Channel (simple-name fallback)",
                type: fixture.classType(["com", "example", "Channel"], kind: .class),
                expected: [.channel]
            ),
            TypeCase(
                name: "user Job (simple-name fallback)",
                type: fixture.classType(["com", "example", "Job"], kind: .class),
                expected: [.coroutineHandle]
            ),
        ]

        let classifier = ReceiverClassifier(sema: fixture.sema, interner: fixture.interner)
        for sample in sourceCases {
            let expected = sample.expected
            #expect(fixture.callLowerer.isRegexLikeType(sample.type, sema: fixture.sema, interner: fixture.interner) == expected.contains(.regex), Comment(rawValue: sample.name))
            #expect(fixture.callLowerer.isSequenceLikeType(sample.type, sema: fixture.sema, interner: fixture.interner) == expected.contains(.sequence), Comment(rawValue: sample.name))
            #expect(fixture.callChecker.isSequenceLikeType(sample.type, sema: fixture.sema, interner: fixture.interner) == expected.contains(.sequence), Comment(rawValue: sample.name))
            #expect(fixture.callLowerer.isConcreteListLikeType(sample.type, sema: fixture.sema, interner: fixture.interner) == expected.contains(.listLike), Comment(rawValue: sample.name))
            #expect(fixture.callChecker.isListLikeType(sample.type, sema: fixture.sema, interner: fixture.interner) == expected.contains(.listLike), Comment(rawValue: sample.name))
            #expect(classifier.isConcreteListLikeType(sample.type) == expected.contains(.strictList), Comment(rawValue: sample.name))
            #expect(classifier.isConcreteListLikeCollectionType(sample.type) == expected.contains(.listCollection), Comment(rawValue: sample.name))
            #expect(
                fixture.callLowerer.isConcreteCollectionLikeType(
                    sample.type,
                    sema: fixture.sema,
                    interner: fixture.interner
                ) == expected.contains(.concreteCollection),
                Comment(rawValue: sample.name)
            )
            #expect(fixture.callChecker.isCollectionLikeType(sample.type, sema: fixture.sema, interner: fixture.interner) == expected.contains(.collectionAggregate), Comment(rawValue: sample.name))
            #expect(classifier.isSetLikeType(sample.type) == expected.contains(.setLike), Comment(rawValue: sample.name))
            #expect(fixture.callLowerer.isSetLikeType(sample.type, sema: fixture.sema, interner: fixture.interner) == expected.contains(.setLike), Comment(rawValue: sample.name))
            #expect(classifier.isSetLikeCollectionType(sample.type) == expected.contains(.strictSet), Comment(rawValue: sample.name))
            #expect(classifier.isMutableSetLikeType(sample.type) == expected.contains(.mutableSetLike), Comment(rawValue: sample.name))
            #expect(fixture.callLowerer.isMutableSetLikeType(sample.type, sema: fixture.sema, interner: fixture.interner) == expected.contains(.mutableSetLike), Comment(rawValue: sample.name))
            #expect(classifier.isMutableSetType(sample.type) == expected.contains(.strictMutableSet), Comment(rawValue: sample.name))
            #expect(classifier.isArrayLikeType(sample.type) == expected.contains(.arrayLike), Comment(rawValue: sample.name))
            #expect(fixture.callLowerer.isConcreteArrayLikeType(sample.type, sema: fixture.sema, interner: fixture.interner) == expected.contains(.concreteArrayLike), Comment(rawValue: sample.name))
            #expect(classifier.isCoroutineHandleReceiverType(sample.type) == expected.contains(.coroutineHandle), Comment(rawValue: sample.name))
            #expect(classifier.isChannelReceiverType(sample.type) == expected.contains(.channel), Comment(rawValue: sample.name))
        }

        // `isCollectionLikeType` deliberately also checks intersections and type
        // parameter bounds. KIR's exact receiver predicate rejects those shapes.
        let unrelated = fixture.classType(["com", "example", "Record"], kind: .class)
        let intersection = fixture.sema.types.make(.intersection([list, unrelated]))
        #expect(classifier.isCollectionLikeType(intersection))
        #expect(!classifier.isConcreteCollectionLikeType(intersection))
        #expect(!fixture.callLowerer.isConcreteCollectionLikeType(intersection, sema: fixture.sema, interner: fixture.interner))
    }

    @Test
    func sourceTypeAliasUsesItsResolvedReceiverType() throws {
        let context = makeContextFromSource("""
        package receiver.aliases

        typealias StringList = kotlin.collections.List<String>

        fun fromAlias(value: StringList) {}
        fun direct(value: kotlin.collections.List<String>) {}
        """)
        try runSema(context)

        let sema = try #require(context.sema)
        let aliasSymbol = try #require(sema.symbols.lookup(fqName: ["receiver", "aliases", "fromAlias"].map(context.interner.intern)))
        let directSymbol = try #require(sema.symbols.lookup(fqName: ["receiver", "aliases", "direct"].map(context.interner.intern)))
        let aliasType = try #require(sema.symbols.functionSignature(for: aliasSymbol)?.parameterTypes.first)
        let directType = try #require(sema.symbols.functionSignature(for: directSymbol)?.parameterTypes.first)
        #expect(aliasType == directType, "A typealias should be erased to its resolved List receiver type")

        let classifier = ReceiverClassifier(sema: sema, interner: context.interner)
        #expect(classifier.isListLikeType(aliasType))
        #expect(classifier.isConcreteListLikeType(aliasType))
        #expect(classifier.isConcreteCollectionLikeType(aliasType))
    }
}
#endif
