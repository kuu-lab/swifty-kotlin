@testable import Runtime
import Testing

@Suite(.runtimeIsolation(.gcAndMetadata))
struct RuntimeRangeClassLiteralTests {
    private var cases: [(RuntimeRangeKind, String)] {
        [(.intRange, "IntRange"), (.intProgression, "IntProgression"),
         (.longRange, "LongRange"), (.longProgression, "LongProgression"),
         (.charRange, "CharRange"), (.charProgression, "CharProgression"),
         (.uintRange, "UIntRange"), (.uintProgression, "UIntProgression"),
         (.ulongRange, "ULongRange"), (.ulongProgression, "ULongProgression")]
    }

    @Test(arguments: [false, true], [false, true])
    func cachedMissingOrShortNamesDoNotChangeRangeNames(metadataPresent: Bool, namedHint: Bool) throws {
        for (kind, simpleName) in cases {
            let qualifiedName = "kotlin.ranges." + simpleName
            let typeID = runtimeStableNominalTypeID(fqName: qualifiedName)
            let token = Int(truncatingIfNeeded:
                (typeID & RuntimeTypeTokenEncoding.payloadMask) << RuntimeTypeTokenEncoding.payloadShift
                    | RuntimeTypeTokenEncoding.nominalBase)
            let shortHint = runtimeMakeStringRaw(simpleName)
            let hint = namedHint ? shortHint : 0
            let cached = __kk_kclass_create(token, hint)
            if metadataPresent {
                _ = __kk_kclass_register_metadata(token, shortHint, shortHint, 0, 0, 0, 0, 0)
            }
            let range = registerRuntimeObject(RuntimeRangeBox(first: 1, last: 2, step: 1, kind: kind))
            #expect(__kk_kclass_of(range, Int(RuntimeTypeTokenEncoding.anyBase), 0) == cached)
            #expect(runtimeRenderAnyForPrint(__kk_type_token_simple_name(token, hint)) == simpleName)
            #expect(runtimeRenderAnyForPrint(__kk_type_token_qualified_name(token, shortHint)) == qualifiedName)
            kk_gc_collect()
            #expect(runtimeRenderAnyForPrint(__kk_kclass_simple_name(cached)) == simpleName)
            #expect(runtimeRenderAnyForPrint(__kk_kclass_qualified_name(cached)) == qualifiedName)
        }
    }

    @Test func unrelatedClassNamedIntRangeKeepsItsQualifiedName() {
        let qualifiedName = "sample.IntRange"
        let typeID = runtimeStableNominalTypeID(fqName: qualifiedName)
        let token = Int(truncatingIfNeeded:
            (typeID & RuntimeTypeTokenEncoding.payloadMask) << RuntimeTypeTokenEncoding.payloadShift
                | RuntimeTypeTokenEncoding.nominalBase)
        _ = __kk_kclass_register_metadata(
            token, runtimeMakeStringRaw(qualifiedName), runtimeMakeStringRaw("IntRange"),
            0, 0, 0, 0, 0
        )
        let value = kk_object_new(0, Int(typeID))
        let actual = __kk_kclass_of(value, Int(RuntimeTypeTokenEncoding.anyBase), 0)
        #expect(runtimeRenderAnyForPrint(__kk_kclass_qualified_name(actual)) == qualifiedName)
        #expect(runtimeRenderAnyForPrint(__kk_type_token_qualified_name(token, 0)) == qualifiedName)
    }

    @Test(arguments: [false, true], [false, true])
    func rangeIdentitySurvivesLiteralAndMetadataRegistrationOrder(literalFirst: Bool, metadataFirst: Bool) throws {
        for (kind, simpleName) in cases {
            let qualifiedName = "kotlin.ranges." + simpleName
            let typeID = runtimeStableNominalTypeID(fqName: qualifiedName)
            let token = Int(truncatingIfNeeded:
                (typeID & RuntimeTypeTokenEncoding.payloadMask) << RuntimeTypeTokenEncoding.payloadShift
                    | RuntimeTypeTokenEncoding.nominalBase)
            let registerMetadata = {
                _ = __kk_kclass_register_metadata(
                    token, runtimeMakeStringRaw(qualifiedName), runtimeMakeStringRaw(simpleName),
                    0, 0, 0, 0, 0
                )
            }
            if metadataFirst { registerMetadata() }
            let literal = literalFirst ? __kk_kclass_create(token, runtimeMakeStringRaw(qualifiedName)) : nil
            let range = registerRuntimeObject(RuntimeRangeBox(first: 1, last: 2, step: 1, kind: kind))
            let actual = __kk_kclass_of(range, Int(RuntimeTypeTokenEncoding.anyBase), runtimeMakeStringRaw("Any"))
            let expectedLiteral = literal ?? __kk_kclass_create(token, runtimeMakeStringRaw(qualifiedName))
            #expect(try #require(runtimeKClassBox(from: actual)).typeToken == token)
            #expect(runtimeRenderAnyForPrint(__kk_kclass_simple_name(actual)) == simpleName)
            #expect(runtimeRenderAnyForPrint(__kk_kclass_qualified_name(actual)) == qualifiedName)
            #expect(actual == expectedLiteral)
            #expect(kk_op_is(range, token) == 1)
            // Collect before late registration so metadata cannot hide a lost name hint.
            kk_gc_collect()
            #expect(runtimeRenderAnyForPrint(__kk_kclass_simple_name(actual)) == simpleName)
            #expect(runtimeRenderAnyForPrint(__kk_kclass_qualified_name(actual)) == qualifiedName)
            if !metadataFirst { registerMetadata() }
            #expect(runtimeRenderAnyForPrint(__kk_kclass_simple_name(actual)) == simpleName)
            #expect(runtimeRenderAnyForPrint(__kk_kclass_qualified_name(actual)) == qualifiedName)
            #expect(__kk_kclass_of(range, Int(RuntimeTypeTokenEncoding.intBase), 0) == actual)
        }
    }
}
