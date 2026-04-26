@testable import CompilerCore
import Foundation
import XCTest

final class RangeSyntheticMemberLinkTests: XCTestCase {
    private func makeSema() throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            result = (sema, ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    private func functionExternalLink(
        for owner: String,
        member: String,
        parameterCount: Int,
        sema: SemaModule,
        interner: StringInterner
    ) -> String? {
        let fq = ["kotlin", "ranges", owner, member].map { interner.intern($0) }
        return sema.symbols.lookupAll(fqName: fq).first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.parameterTypes.count == parameterCount
        }.flatMap { sema.symbols.externalLinkName(for: $0) }
    }

    func testCharProgressionSyntheticSurface() throws {
        let (sema, interner) = try makeSema()
        let charProgressionFQName = ["kotlin", "ranges", "CharProgression"].map { interner.intern($0) }
        let charProgressionSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: charProgressionFQName))
        let charProgressionType = sema.types.make(.classType(ClassType(
            classSymbol: charProgressionSymbol,
            args: [],
            nullability: .nonNull
        )))
        let companionSymbol = try XCTUnwrap(sema.symbols.companionObjectSymbol(for: charProgressionSymbol))
        let companionInfo = try XCTUnwrap(sema.symbols.symbol(companionSymbol))
        let fromClosedRangeSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: companionInfo.fqName + [interner.intern("fromClosedRange")])
        )
        let fromClosedRangeSignature = try XCTUnwrap(sema.symbols.functionSignature(for: fromClosedRangeSymbol))

        XCTAssertEqual(sema.symbols.externalLinkName(for: fromClosedRangeSymbol), "kk_char_progression_fromClosedRange")
        XCTAssertEqual(fromClosedRangeSignature.parameterTypes, [sema.types.charType, sema.types.charType, sema.types.intType])
        XCTAssertEqual(fromClosedRangeSignature.returnType, charProgressionType)
        XCTAssertEqual(
            functionExternalLink(
                for: "CharProgression",
                member: "toList",
                parameterCount: 0,
                sema: sema,
                interner: interner
            ),
            "kk_char_range_toList"
        )
        XCTAssertEqual(
            functionExternalLink(
                for: "CharProgression",
                member: "isEmpty",
                parameterCount: 0,
                sema: sema,
                interner: interner
            ),
            "kk_char_range_isEmpty"
        )
        XCTAssertEqual(
            functionExternalLink(
                for: "CharProgression",
                member: "step",
                parameterCount: 1,
                sema: sema,
                interner: interner
            ),
            "kk_char_range_step"
        )
    }
}
