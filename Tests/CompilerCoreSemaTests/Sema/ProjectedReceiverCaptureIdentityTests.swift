#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct ProjectedReceiverCaptureIdentityTests {
    @Test
    func repeatedProjectionCaptureIsReflexiveButIndependentCapturesAreNot() {
        let types = TypeSystem()
        let parameter = SymbolID(rawValue: 1)
        let receiver = types.make(.classType(ClassType(
            classSymbol: SymbolID(rawValue: 2),
            args: [.out(types.stringType)]
        )))

        let first = types.makeProjectedReceiverCapture(
            receiverType: receiver,
            parameter: parameter,
            lower: types.nothingType,
            upper: types.stringType,
            writeForbidden: true,
            argumentIndex: 0
        )
        let repeated = types.makeProjectedReceiverCapture(
            receiverType: receiver,
            parameter: parameter,
            lower: types.nothingType,
            upper: types.stringType,
            writeForbidden: true,
            argumentIndex: 0
        )
        #expect(first != repeated)
        #expect(types.isSubtype(first, repeated))
        #expect(types.isSubtype(repeated, first))

        let otherReceiver = types.make(.classType(ClassType(
            classSymbol: SymbolID(rawValue: 3),
            args: [.out(types.stringType)]
        )))
        let independentProjection = types.makeProjectedReceiverCapture(
            receiverType: otherReceiver,
            parameter: parameter,
            lower: types.nothingType,
            upper: types.stringType,
            writeForbidden: true,
            argumentIndex: 0
        )
        let independentCapture = types.makeCapturedType(
            parameter: parameter,
            lower: types.nothingType,
            upper: types.stringType,
            writeForbidden: true
        )
        #expect(!types.isSubtype(first, independentProjection))
        #expect(!types.isSubtype(first, independentCapture))
    }

    @Test
    func workerMergeRemapsCapturedBoundsAndProjectionOrigin() throws {
        let types = TypeSystem()
        let worker = types.makeSemaWorkerTypes()
        let prefix = worker.internedTypeCount
        let receiver = worker.make(.classType(ClassType(classSymbol: SymbolID(rawValue: 10))))
        let captured = worker.makeProjectedReceiverCapture(
            receiverType: receiver,
            parameter: SymbolID(rawValue: 11),
            lower: worker.nothingType,
            upper: receiver,
            writeForbidden: true,
            argumentIndex: 0
        )

        _ = types.make(.classType(ClassType(classSymbol: SymbolID(rawValue: 12))))
        let mapping = types.mergeWorkerTypes(worker.workerTypeKinds(since: prefix), startingAt: prefix)
        let canonicalReceiver = try #require(mapping[receiver])
        let canonicalCapture = try #require(mapping[captured])
        guard case let .typeParam(parameter) = types.kind(of: canonicalCapture),
              let bounds = parameter.capture
        else {
            Issue.record("Expected the merged type to remain a captured type parameter.")
            return
        }

        #expect(bounds.upper == canonicalReceiver)
        #expect(bounds.origin?.receiverType == canonicalReceiver)
    }
}
#endif
