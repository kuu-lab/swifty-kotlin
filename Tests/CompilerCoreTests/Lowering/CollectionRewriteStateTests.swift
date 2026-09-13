#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct CollectionRewriteStateTests {
    private typealias State = CollectionLiteralLoweringSupport.CollectionRewriteState
    private typealias Classification = CollectionLiteralLoweringSupport.Classification
    private typealias Facts = CollectionLiteralLoweringSupport.ClassificationFacts
    private typealias Axis = CollectionLiteralLoweringSupport.ClassificationAxis

    private var classifications: [WritableKeyPath<State, Set<Int32>>] {
        [
            \.listExprIDs, \.setExprIDs, \.mapExprIDs, \.arrayExprIDs,
            \.sequenceExprIDs, \.rangeExprIDs, \.charRangeExprIDs,
            \.ulongRangeExprIDs, \.stringExprIDs, \.fileExprIDs, \.pathExprIDs,
            \.listIteratorExprIDs, \.mapIteratorExprIDs, \.iteratorBuilderExprIDs,
            \.indexingIterableExprIDs, \.indexingIterableIteratorExprIDs,
            \.ulongRangeIteratorExprIDs,
        ]
    }

    @Test
    func copiesPreserveEachClassificationThroughMultipleAliases() {
        let source = KIRExprID(rawValue: 1)
        let alias = KIRExprID(rawValue: 2)
        let secondAlias = KIRExprID(rawValue: 3)
        for classification in classifications {
            var state = State()
            state[keyPath: classification].insert(source.rawValue)
            state.propagateCopy(from: source, to: alias)
            state.propagateCopy(from: alias, to: secondAlias)

            for observed in classifications {
                let expected: Set<Int32> = observed == classification ? [1, 2, 3] : []
                #expect(state[keyPath: observed] == expected)
            }
        }
    }

    @Test
    func rangeCopiesRetainGeneralAndSpecializedFactsTogether() {
        let charRange = KIRExprID(rawValue: 1)
        let unsignedRange = KIRExprID(rawValue: 2)
        let charAlias = KIRExprID(rawValue: 3)
        let unsignedAlias = KIRExprID(rawValue: 4)
        var state = State()
        state.rangeExprIDs = [1, 2]
        state.charRangeExprIDs = [1]
        state.ulongRangeExprIDs = [2]

        state.propagateCopy(from: charRange, to: charAlias)
        state.propagateCopy(from: unsignedRange, to: unsignedAlias)

        #expect(state.rangeExprIDs == [1, 2, 3, 4])
        #expect(state.charRangeExprIDs == [1, 3])
        #expect(state.ulongRangeExprIDs == [2, 4])
    }

    @Test
    func reassigningStorageReplacesItsPreviousClassification() {
        let list = KIRExprID(rawValue: 1)
        let map = KIRExprID(rawValue: 2)
        let storage = KIRExprID(rawValue: 3)
        let priorAlias = KIRExprID(rawValue: 4)
        var state = State()
        state.listExprIDs = [list.rawValue]
        state.mapExprIDs = [map.rawValue]

        state.propagateCopy(from: list, to: storage)
        state.propagateCopy(from: storage, to: priorAlias)
        state.propagateCopy(from: map, to: storage)

        #expect(state.listExprIDs == [list.rawValue, priorAlias.rawValue])
        #expect(state.mapExprIDs == [map.rawValue, storage.rawValue])
    }

    @Test
    func reassigningAnUnknownValueClearsEveryRuntimeClassification() {
        let unknown = KIRExprID(rawValue: 1)
        let storage = KIRExprID(rawValue: 2)
        for classification in classifications {
            var state = State()
            state[keyPath: classification].insert(storage.rawValue)

            state.propagateCopy(from: unknown, to: storage)

            for observed in classifications {
                #expect(state[keyPath: observed].isEmpty)
            }
        }
    }

    @Test
    func seedingCopiesAddSourceFactsWithoutDroppingDestinationFacts() {
        let source = KIRExprID(rawValue: 1)
        let destination = KIRExprID(rawValue: 2)
        for classification in classifications {
            var state = State()
            state[keyPath: classification].insert(destination.rawValue)

            // The pre-scan seeds one body forward, so an unclassified source
            // says nothing about the destination's own facts. `propagateCopy`
            // is the operation that treats a copy as a reassignment.
            state.seedCopy(from: source, to: destination)
            #expect(state[keyPath: classification] == [destination.rawValue])

            state[keyPath: classification].insert(source.rawValue)
            state.seedCopy(from: source, to: destination)
            for observed in classifications {
                let expected: Set<Int32> = observed == classification ? [1, 2] : []
                #expect(state[keyPath: observed] == expected)
            }
        }
    }

    @Test
    func selfCopyPreservesOverlappingRangeFacts() {
        let range = KIRExprID(rawValue: 1)
        var state = State()
        state.rangeExprIDs = [1]
        state.ulongRangeExprIDs = [1]

        state.propagateCopy(from: range, to: range)

        #expect(state.rangeExprIDs == [1])
        #expect(state.ulongRangeExprIDs == [1])
        #expect(state.charRangeExprIDs.isEmpty)
    }

    // MARK: - Storage manifest

    @Test
    func namedAccessorsCoverEveryClassificationExactlyOnce() {
        #expect(classifications.count == Classification.allCases.count)

        // Probe which classification each named accessor writes to, so a
        // mis-paired manifest entry cannot hide behind matching counts.
        var covered: [Classification] = []
        for (index, accessor) in classifications.enumerated() {
            var state = State()
            let probe = KIRExprID(rawValue: Int32(index) + 1)
            state[keyPath: accessor].insert(probe.rawValue)

            let matches = Classification.allCases.filter { state.contains($0, probe) }
            #expect(matches.count == 1)
            covered.append(contentsOf: matches)
        }
        #expect(Set(covered.map(\.rawValue)).count == Classification.allCases.count)
    }

    @Test
    func mutatingAndReadingTheManifestReachTheSameStorage() {
        for classification in Classification.allCases {
            var state = State()
            let expr = KIRExprID(rawValue: 42)
            state.mutateMembership(of: classification) { $0.insert(expr.rawValue) }

            #expect(state.membership(of: classification) == [expr.rawValue])
            #expect(state.contains(classification, expr))
            for other in Classification.allCases where other != classification {
                #expect(state.membership(of: other).isEmpty)
            }

            state.remove(classification, expr)
            #expect(state.membership(of: classification).isEmpty)
        }
    }

    @Test
    func factsBitPositionsFollowClassificationRawValues() {
        for classification in Classification.allCases {
            #expect(Facts(classification).rawValue == 1 << UInt32(classification.rawValue))
            #expect(Facts(classification).classifications == [classification])
        }
        let everything = Classification.allCases.reduce(into: Facts()) { $0.insert(Facts($1)) }
        #expect(everything.classifications == Classification.allCases)
    }

    // MARK: - Expression-keyed access

    @Test
    func expressionKeyedFactsAgreeWithTheNamedAccessors() {
        var state = State()
        let expr = KIRExprID(rawValue: 7)
        state.rangeExprIDs.insert(expr.rawValue)
        state.ulongRangeExprIDs.insert(expr.rawValue)

        #expect(state[expr] == [Facts(.range), Facts(.ulongRange)])
        #expect(state[expr].classifications == [.range, .ulongRange])
        #expect(state[KIRExprID(rawValue: 8)].isEmpty)

        state[expr] = [Facts(.map), Facts(.mapIterator)]
        #expect(state.mapExprIDs == [expr.rawValue])
        #expect(state.mapIteratorExprIDs == [expr.rawValue])
        #expect(state.rangeExprIDs.isEmpty)
        #expect(state.ulongRangeExprIDs.isEmpty)
    }

    @Test
    func assigningFactsLeavesOtherExpressionsAlone() {
        var state = State()
        let kept = KIRExprID(rawValue: 1)
        let replaced = KIRExprID(rawValue: 2)
        state.listExprIDs = [kept.rawValue, replaced.rawValue]

        state[replaced] = [Facts(.set)]

        #expect(state.listExprIDs == [kept.rawValue])
        #expect(state.setExprIDs == [replaced.rawValue])
    }

    // MARK: - Compatibility with the old inout plumbing

    @Test
    func inoutWriteBackAndTheStoreStayConsistent() {
        // The registry hands individual sets to callees as `inout Set<Int32>`;
        // whatever they write back must be visible through the store API.
        func seed(_ expressions: inout Set<Int32>) {
            expressions.insert(10)
            expressions.insert(11)
            expressions.remove(10)
        }

        var state = State()
        seed(&state.listExprIDs)

        #expect(state.contains(.list, KIRExprID(rawValue: 11)))
        #expect(!state.contains(.list, KIRExprID(rawValue: 10)))
        #expect(state[KIRExprID(rawValue: 11)] == [Facts(.list)])

        // And the reverse direction: a store mutation is visible through both
        // the `inout` accessor and the by-value read the registry uses for
        // `iteratorBuilderExprIDs`.
        state.insert(.iteratorBuilder, KIRExprID(rawValue: 12))
        func observe(_ expressions: Set<Int32>) -> Bool { expressions.contains(12) }
        #expect(observe(state.iteratorBuilderExprIDs))
    }

    @Test
    func separateClassificationsStayIndependentAcrossSimultaneousInoutArguments() {
        // Mirrors the registry call sites, which pass more than one set to the
        // same callee. This only compiles while the named sets are distinct
        // storage rather than computed views.
        func seedBoth(_ lists: inout Set<Int32>, _ sets: inout Set<Int32>) {
            lists.insert(1)
            sets.insert(2)
        }

        var state = State()
        seedBoth(&state.listExprIDs, &state.setExprIDs)

        #expect(state[KIRExprID(rawValue: 1)] == [Facts(.list)])
        #expect(state[KIRExprID(rawValue: 2)] == [Facts(.set)])
    }

    // MARK: - Axes

    @Test
    func axesPartitionEveryClassification() {
        for classification in Classification.allCases {
            let own = Facts.mask(for: classification.axis)
            #expect(own.contains(classification))
            for other in Axis.allCases where other != classification.axis {
                #expect(!Facts.mask(for: other).contains(classification))
            }
        }
        #expect(Facts.staticType.isDisjoint(with: .runtimeRepresentation))
        #expect(Facts.staticType.union(.runtimeRepresentation).classifications == Classification.allCases)
    }

    @Test
    func unknownIsAskedPerAxisRatherThanGlobally() {
        var state = State()
        let expr = KIRExprID(rawValue: 1)
        #expect(state[expr].isUnknown(on: .staticType))
        #expect(state[expr].isUnknown(on: .runtimeRepresentation))

        // A value whose runtime handle lowering materialised is classified on
        // the runtime axis while still unknown on the static-type axis.
        state.insert(.listIterator, expr)
        #expect(!state[expr].isUnknown(on: .runtimeRepresentation))
        #expect(state[expr].isUnknown(on: .staticType))
        #expect(state[expr].facts(on: .runtimeRepresentation).classifications == [.listIterator])
        #expect(state[expr].facts(on: .staticType).isEmpty)

        state.insert(.list, expr)
        #expect(!state[expr].isUnknown(on: .staticType))
        #expect(state[expr].facts(on: .staticType).classifications == [.list])
    }

    // MARK: - Result tagging

    @Test
    func tagResultMarksBothTheResultAndItsTemporary() {
        var state = State()
        state.tagListResult(KIRExprID(rawValue: 1), temporary: KIRExprID(rawValue: 2))
        state.tagMapResult(KIRExprID(rawValue: 3))
        state.tagResult(.sequence, KIRExprID(rawValue: 4), temporary: KIRExprID(rawValue: 5))
        state.tagListResult(nil, temporary: KIRExprID(rawValue: 9))

        #expect(state.listExprIDs == [1, 2])
        #expect(state.mapExprIDs == [3])
        #expect(state.sequenceExprIDs == [4, 5])
        #expect(!state.contains(.list, KIRExprID(rawValue: 9)))
    }
}
#endif
