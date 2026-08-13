// swiftlint:disable file_length

/// Shared helpers for collection higher-order function ABI specs.
public extension RuntimeABISpec {
    static let hofLambdaParams: [RuntimeABIParameter] = [
        RuntimeABIParameter(name: "listRaw", type: .intptr),
        RuntimeABIParameter(name: "fnPtr", type: .intptr),
        RuntimeABIParameter(name: "closureRaw", type: .intptr),
        RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
    ]

    static func hofSpec(_ name: String) -> RuntimeABIFunctionSpec {
        RuntimeABIFunctionSpec(
            name: name, parameters: hofLambdaParams,
            returnType: .intptr, section: "Collection"
        )
    }

    private static func stdlibListHOFName(_ memberName: String, arity: Int, fallback: String) -> String {
        StdlibSurfaceSpec.collectionHOFRuntimeLinkName(
            ownerKind: .list,
            memberName: memberName,
            arity: arity,
            fallback: fallback
        )
    }

    private static func stdlibListHOFSpec(_ memberName: String, arity: Int, fallback: String) -> RuntimeABIFunctionSpec {
        hofSpec(stdlibListHOFName(memberName, arity: arity, fallback: fallback))
    }

    static let collectionHOFFunctions: [RuntimeABIFunctionSpec] = {
        let before = [
            "kk_list_forEach",
        ]
        let destinationLambdaParams = [
            RuntimeABIParameter(name: "listRaw", type: .intptr),
            RuntimeABIParameter(name: "destRaw", type: .intptr),
            RuntimeABIParameter(name: "fnPtr", type: .intptr),
            RuntimeABIParameter(name: "closureRaw", type: .intptr),
            RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
        ]
        let requireNoNullsSpec = RuntimeABIFunctionSpec(
            name: "__kk_iterable_requireNoNulls",
            parameters: [
                RuntimeABIParameter(name: "iterableRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Collection"
        )

        let firstNotNullOfSpec = RuntimeABIFunctionSpec(
            name: "__kk_iterable_firstNotNullOf",
            parameters: [
                RuntimeABIParameter(name: "iterableRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Collection"
        )
        let firstNotNullOfOrNullSpec = RuntimeABIFunctionSpec(
            name: "__kk_iterable_firstNotNullOfOrNull",
            parameters: [
                RuntimeABIParameter(name: "iterableRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Collection"
        )
        let iterableAllSpec = RuntimeABIFunctionSpec(
            name: "__kk_iterable_all",
            parameters: [
                RuntimeABIParameter(name: "iterableRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Collection"
        )
        let iterableAnySpec = RuntimeABIFunctionSpec(
            name: "__kk_iterable_any",
            parameters: [
                RuntimeABIParameter(name: "iterableRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Collection"
        )
        let iterableLastSpec = RuntimeABIFunctionSpec(
            name: "__kk_iterable_last",
            parameters: [
                RuntimeABIParameter(name: "iterableRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Collection"
        )

        let associateBySpec = RuntimeABIFunctionSpec(
            name: "kk_list_associateBy",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Collection"
        )
        let associateByTransformSpec = RuntimeABIFunctionSpec(
            name: "kk_list_associateByTransform",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
                RuntimeABIParameter(name: "keyFnPtr", type: .intptr),
                RuntimeABIParameter(name: "keyClosureRaw", type: .intptr),
                RuntimeABIParameter(name: "valueFnPtr", type: .intptr),
                RuntimeABIParameter(name: "valueClosureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Collection"
        )
        let associateWithSpec = RuntimeABIFunctionSpec(
            name: "kk_list_associateWith",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Collection"
        )
        let associateSpec = RuntimeABIFunctionSpec(
            name: "kk_list_associate",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Collection"
        )
        let associateToSpec = RuntimeABIFunctionSpec(
            name: "kk_list_associateTo",
            parameters: destinationLambdaParams,
            returnType: .intptr,
            section: "Collection"
        )
        let listWindowChunkReceiverSizeParams = [
            RuntimeABIParameter(name: "listRaw", type: .intptr),
            RuntimeABIParameter(name: "size", type: .intptr),
        ]
        let listWindowChunkReceiverSizeLambdaParams = [
            RuntimeABIParameter(name: "listRaw", type: .intptr),
            RuntimeABIParameter(name: "size", type: .intptr),
            RuntimeABIParameter(name: "fnPtr", type: .intptr),
            RuntimeABIParameter(name: "closureRaw", type: .intptr),
            RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
        ]
        let listWindowedParams = [
            RuntimeABIParameter(name: "listRaw", type: .intptr),
            RuntimeABIParameter(name: "size", type: .intptr),
            RuntimeABIParameter(name: "step", type: .intptr),
            RuntimeABIParameter(name: "partialWindows", type: .intptr),
        ]
        let listWindowedTransformParams = [
            RuntimeABIParameter(name: "listRaw", type: .intptr),
            RuntimeABIParameter(name: "size", type: .intptr),
            RuntimeABIParameter(name: "step", type: .intptr),
            RuntimeABIParameter(name: "partialWindows", type: .intptr),
            RuntimeABIParameter(name: "fnPtr", type: .intptr),
            RuntimeABIParameter(name: "closureRaw", type: .intptr),
            RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
        ]
        let listZipParams = [
            RuntimeABIParameter(name: "listRaw", type: .intptr),
            RuntimeABIParameter(name: "otherRaw", type: .intptr),
        ]
        let listZipTransformParams = [
            RuntimeABIParameter(name: "listRaw", type: .intptr),
            RuntimeABIParameter(name: "otherRaw", type: .intptr),
            RuntimeABIParameter(name: "fnPtr", type: .intptr),
            RuntimeABIParameter(name: "closureRaw", type: .intptr),
            RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
        ]
        let legacyListZipTransformSpec = RuntimeABIFunctionSpec(
            name: "kk_list_zip_transform",
            parameters: listZipTransformParams,
            returnType: .intptr,
            section: "Collection"
        )
        let listWindowChunkBridgeSpecs = [
            RuntimeABIFunctionSpec(
                name: "__kk_list_chunked",
                parameters: listWindowChunkReceiverSizeParams,
                returnType: .intptr,
                section: "Collection",
                isThrowing: false
            ),
            RuntimeABIFunctionSpec(
                name: "__kk_list_chunked_transform",
                parameters: listWindowChunkReceiverSizeLambdaParams,
                returnType: .intptr,
                section: "Collection"
            ),
            RuntimeABIFunctionSpec(
                name: "__kk_list_windowed",
                parameters: listWindowedParams,
                returnType: .intptr,
                section: "Collection",
                isThrowing: false
            ),
            RuntimeABIFunctionSpec(
                name: "__kk_list_windowed_transform",
                parameters: listWindowedTransformParams,
                returnType: .intptr,
                section: "Collection"
            ),
            RuntimeABIFunctionSpec(
                name: "__kk_list_zip",
                parameters: listZipParams,
                returnType: .intptr,
                section: "Collection",
                isThrowing: false
            ),
            RuntimeABIFunctionSpec(
                name: "__kk_list_zip_transform",
                parameters: listZipTransformParams,
                returnType: .intptr,
                section: "Collection"
            ),
            RuntimeABIFunctionSpec(
                name: "__kk_list_zipWithNext",
                parameters: [
                    RuntimeABIParameter(name: "listRaw", type: .intptr),
                ],
                returnType: .intptr,
                section: "Collection",
                isThrowing: false
            ),
            RuntimeABIFunctionSpec(
                name: "__kk_list_zipWithNextTransform",
                parameters: [
                    RuntimeABIParameter(name: "listRaw", type: .intptr),
                    RuntimeABIParameter(name: "fnPtr", type: .intptr),
                    RuntimeABIParameter(name: "closureRaw", type: .intptr),
                    RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
                ],
                returnType: .intptr,
                section: "Collection"
            ),
        ]
        let unzipSpec = RuntimeABIFunctionSpec(
            name: "kk_list_unzip",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        )
        let sumOfSpec = RuntimeABIFunctionSpec(
            name: "kk_list_sumOf",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Collection"
        )
        let sumBySpec = RuntimeABIFunctionSpec(
            name: "kk_list_sumBy",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Collection"
        )
        let sumByDoubleSpec = RuntimeABIFunctionSpec(
            name: "kk_list_sumByDouble",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Collection"
        )
        let maxOrNullSpec = RuntimeABIFunctionSpec(
            name: "kk_list_maxOrNull",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        )
        let minOrNullSpec = RuntimeABIFunctionSpec(
            name: "kk_list_minOrNull",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        )
        let maxSpec = RuntimeABIFunctionSpec(
            name: "kk_list_max",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Collection"
        )
        let minSpec = RuntimeABIFunctionSpec(
            name: "kk_list_min",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Collection"
        )
        let sumSpec = RuntimeABIFunctionSpec(
            name: "kk_list_sum",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        )
        let averageSpec = RuntimeABIFunctionSpec(
            name: "kk_list_average",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        )
        let reversedSpec = RuntimeABIFunctionSpec(
            name: "kk_list_reversed",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        )
        let asReversedSpec = RuntimeABIFunctionSpec(
            name: "kk_list_as_reversed",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        )
        let sortedSpec = RuntimeABIFunctionSpec(
            name: "kk_list_sorted",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        )
        let sortedPrimitiveSpec = RuntimeABIFunctionSpec(
            name: "kk_list_sorted_primitive",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
                RuntimeABIParameter(name: "kindRaw", type: .int32),
            ],
            returnType: .intptr,
            section: "Collection"
        )
        let distinctSpec = RuntimeABIFunctionSpec(
            name: "kk_list_distinct",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        )
        let shuffledSpec = RuntimeABIFunctionSpec(
            name: "kk_list_shuffled",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        )
        let shuffledRandomSpec = RuntimeABIFunctionSpec(
            name: "kk_list_shuffled_random",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
                RuntimeABIParameter(name: "randomRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        )
        let randomSpec = RuntimeABIFunctionSpec(
            name: "kk_list_random",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Collection"
        )
        let randomOrNullSpec = RuntimeABIFunctionSpec(
            name: "kk_list_randomOrNull",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        )
        let sortedByPrimitiveSpec = RuntimeABIFunctionSpec(
            name: "kk_list_sortedBy_primitive",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "kindRaw", type: .int32),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Collection"
        )
        let genericAfter = [
            "kk_list_groupBy",
            "kk_list_sortedBy",
        ]
        var functions: [RuntimeABIFunctionSpec] = []
        functions.append(contentsOf: before.map { hofSpec($0) })
        functions.append(contentsOf: [requireNoNullsSpec])
        functions.append(contentsOf: [
                firstNotNullOfSpec, firstNotNullOfOrNullSpec,
                iterableAllSpec, iterableAnySpec, iterableLastSpec,
            ])
        functions.append(
            contentsOf: genericAfter.flatMap { name in
                if name == "kk_list_sortedBy" {
                    return [hofSpec(name), sortedByPrimitiveSpec]
                }
                return [hofSpec(name)]
            }
        )

        functions.append(contentsOf: [
                associateBySpec, associateByTransformSpec, associateWithSpec, associateSpec, associateToSpec,
                RuntimeABIFunctionSpec(
                    name: "kk_list_associateByTo",
                    parameters: [
                        RuntimeABIParameter(name: "listRaw", type: .intptr),
                        RuntimeABIParameter(name: "destRaw", type: .intptr),
                        RuntimeABIParameter(name: "fnPtr", type: .intptr),
                        RuntimeABIParameter(name: "closureRaw", type: .intptr),
                        RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
                    ],
                    returnType: .intptr,
                    section: "Collection"
                ),
                RuntimeABIFunctionSpec(
                    name: "kk_list_associateWithTo",
                    parameters: [
                        RuntimeABIParameter(name: "listRaw", type: .intptr),
                        RuntimeABIParameter(name: "destRaw", type: .intptr),
                        RuntimeABIParameter(name: "fnPtr", type: .intptr),
                        RuntimeABIParameter(name: "closureRaw", type: .intptr),
                        RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
                    ],
                    returnType: .intptr,
                    section: "Collection"
                ),
                RuntimeABIFunctionSpec(
                    name: "kk_list_groupByTo",
                    parameters: [
                        RuntimeABIParameter(name: "listRaw", type: .intptr),
                        RuntimeABIParameter(name: "destRaw", type: .intptr),
                        RuntimeABIParameter(name: "fnPtr", type: .intptr),
                        RuntimeABIParameter(name: "closureRaw", type: .intptr),
                        RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
                    ],
                    returnType: .intptr,
                    section: "Collection"
                ),
                RuntimeABIFunctionSpec(
                    name: "kk_list_groupByTransform",
                    parameters: [
                        RuntimeABIParameter(name: "listRaw", type: .intptr),
                        RuntimeABIParameter(name: "keyFnPtr", type: .intptr),
                        RuntimeABIParameter(name: "keyClosureRaw", type: .intptr),
                        RuntimeABIParameter(name: "valueFnPtr", type: .intptr),
                        RuntimeABIParameter(name: "valueClosureRaw", type: .intptr),
                        RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
                    ],
                    returnType: .intptr,
                    section: "Collection"
                ),
            ]
            + [legacyListZipTransformSpec]
            + listWindowChunkBridgeSpecs
            + [
                unzipSpec,
                sumOfSpec, sumBySpec, sumByDoubleSpec, maxOrNullSpec, minOrNullSpec,
                maxSpec, minSpec,
                sumSpec, averageSpec, reversedSpec, asReversedSpec, sortedSpec, distinctSpec,
                sortedPrimitiveSpec,
                shuffledSpec, shuffledRandomSpec, randomSpec, randomOrNullSpec,

                RuntimeABIFunctionSpec(
                    name: "kk_list_binarySearchBy",
                    parameters: [
                        RuntimeABIParameter(name: "listRaw", type: .intptr),
                        RuntimeABIParameter(name: "key", type: .intptr),
                        RuntimeABIParameter(name: "fnPtr", type: .intptr),
                        RuntimeABIParameter(name: "closureRaw", type: .intptr),
                        RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
                    ],
                    returnType: .intptr,
                    section: "Collection"
                ),
                RuntimeABIFunctionSpec(
                    name: "kk_list_binarySearchBy_fromIndex",
                    parameters: [
                        RuntimeABIParameter(name: "listRaw", type: .intptr),
                        RuntimeABIParameter(name: "key", type: .intptr),
                        RuntimeABIParameter(name: "fromIndex", type: .intptr),
                        RuntimeABIParameter(name: "fnPtr", type: .intptr),
                        RuntimeABIParameter(name: "closureRaw", type: .intptr),
                        RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
                    ],
                    returnType: .intptr,
                    section: "Collection"
                ),
                RuntimeABIFunctionSpec(
                    name: "kk_list_binarySearchBy_range",
                    parameters: [
                        RuntimeABIParameter(name: "listRaw", type: .intptr),
                        RuntimeABIParameter(name: "key", type: .intptr),
                        RuntimeABIParameter(name: "fromIndex", type: .intptr),
                        RuntimeABIParameter(name: "toIndex", type: .intptr),
                        RuntimeABIParameter(name: "fnPtr", type: .intptr),
                        RuntimeABIParameter(name: "closureRaw", type: .intptr),
                        RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
                    ],
                    returnType: .intptr,
                    section: "Collection"
                ),
                hofSpec("kk_list_binarySearch_compare"),
                RuntimeABIFunctionSpec(
                    name: "kk_list_binarySearch_comparator",
                    parameters: [
                        RuntimeABIParameter(name: "listRaw", type: .intptr),
                        RuntimeABIParameter(name: "element", type: .intptr),
                        RuntimeABIParameter(name: "fnPtr", type: .intptr),
                        RuntimeABIParameter(name: "closureRaw", type: .intptr),
                        RuntimeABIParameter(name: "fromIndex", type: .intptr),
                        RuntimeABIParameter(name: "toIndex", type: .intptr),
                        RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
                    ],
                    returnType: .intptr,
                    section: "Collection"
                ),
                RuntimeABIFunctionSpec(
                    name: "kk_list_sortedDescending",
                    parameters: [
                        RuntimeABIParameter(name: "listRaw", type: .intptr),
                    ],
                    returnType: .intptr,
                    section: "Collection",
            isThrowing: false
                ),
                RuntimeABIFunctionSpec(
                    name: "kk_list_sortedDescending_primitive",
                    parameters: [
                        RuntimeABIParameter(name: "listRaw", type: .intptr),
                        RuntimeABIParameter(name: "kindRaw", type: .int32),
                    ],
                    returnType: .intptr,
                    section: "Collection"
                ),
                RuntimeABIFunctionSpec(
                    name: "kk_list_sortedByDescending",
                    parameters: hofLambdaParams,
                    returnType: .intptr,
                    section: "Collection"
                ),
                RuntimeABIFunctionSpec(
                    name: "kk_list_sortedByDescending_primitive",
                    parameters: [
                        RuntimeABIParameter(name: "listRaw", type: .intptr),
                        RuntimeABIParameter(name: "fnPtr", type: .intptr),
                        RuntimeABIParameter(name: "closureRaw", type: .intptr),
                        RuntimeABIParameter(name: "kindRaw", type: .int32),
                        RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
                    ],
                    returnType: .intptr,
                    section: "Collection"
                ),
                hofSpec("kk_list_sortedWith"),
                hofSpec("kk_list_partition"),
                RuntimeABIFunctionSpec(
                    name: "kk_list_maxBy",
                    parameters: [
                        RuntimeABIParameter(name: "listRaw", type: .intptr),
                        RuntimeABIParameter(name: "fnPtr", type: .intptr),
                        RuntimeABIParameter(name: "closureRaw", type: .intptr),
                        RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
                    ],
                    returnType: .intptr,
                    section: "Collection"
                ),
                RuntimeABIFunctionSpec(
                    name: "kk_list_maxByOrNull",
                    parameters: [
                        RuntimeABIParameter(name: "listRaw", type: .intptr),
                        RuntimeABIParameter(name: "fnPtr", type: .intptr),
                        RuntimeABIParameter(name: "closureRaw", type: .intptr),
                        RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
                    ],
                    returnType: .intptr,
                    section: "Collection"
                ),
                RuntimeABIFunctionSpec(
                    name: "kk_list_minByOrNull",
                    parameters: [
                        RuntimeABIParameter(name: "listRaw", type: .intptr),
                        RuntimeABIParameter(name: "fnPtr", type: .intptr),
                        RuntimeABIParameter(name: "closureRaw", type: .intptr),
                        RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
                    ],
                    returnType: .intptr,
                    section: "Collection"
                ),
                RuntimeABIFunctionSpec(
                    name: "kk_list_minBy",
                    parameters: [
                        RuntimeABIParameter(name: "listRaw", type: .intptr),
                        RuntimeABIParameter(name: "fnPtr", type: .intptr),
                        RuntimeABIParameter(name: "closureRaw", type: .intptr),
                        RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
                    ],
                    returnType: .intptr,
                    section: "Collection"
                ),
                RuntimeABIFunctionSpec(
                    name: "kk_list_maxOfOrNull",
                    parameters: [
                        RuntimeABIParameter(name: "listRaw", type: .intptr),
                        RuntimeABIParameter(name: "fnPtr", type: .intptr),
                        RuntimeABIParameter(name: "closureRaw", type: .intptr),
                        RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
                    ],
                    returnType: .intptr,
                    section: "Collection"
                ),
                RuntimeABIFunctionSpec(
                    name: "kk_list_minOfOrNull",
                    parameters: [
                        RuntimeABIParameter(name: "listRaw", type: .intptr),
                        RuntimeABIParameter(name: "fnPtr", type: .intptr),
                        RuntimeABIParameter(name: "closureRaw", type: .intptr),
                        RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
                    ],
                    returnType: .intptr,
                    section: "Collection"
                ),
                RuntimeABIFunctionSpec(
                    name: "kk_list_plus_element",
                    parameters: [
                        RuntimeABIParameter(name: "listRaw", type: .intptr),
                        RuntimeABIParameter(name: "element", type: .intptr),
                    ],
                    returnType: .intptr,
                    section: "Collection",
            isThrowing: false
                ),
                RuntimeABIFunctionSpec(
                    name: "kk_list_plus_collection",
                    parameters: [
                        RuntimeABIParameter(name: "listRaw", type: .intptr),
                        RuntimeABIParameter(name: "otherList", type: .intptr),
                    ],
                    returnType: .intptr,
                    section: "Collection",
            isThrowing: false
                ),
                RuntimeABIFunctionSpec(
                    name: "kk_list_minus_element",
                    parameters: [
                        RuntimeABIParameter(name: "listRaw", type: .intptr),
                        RuntimeABIParameter(name: "element", type: .intptr),
                    ],
                    returnType: .intptr,
                    section: "Collection",
            isThrowing: false
                ),
                RuntimeABIFunctionSpec(
                    name: "kk_list_minus_collection",
                    parameters: [
                        RuntimeABIParameter(name: "listRaw", type: .intptr),
                        RuntimeABIParameter(name: "otherList", type: .intptr),
                    ],
                    returnType: .intptr,
                    section: "Collection",
            isThrowing: false
                ),
                RuntimeABIFunctionSpec(
                    name: "kk_list_binarySearch",
                    parameters: [
                        RuntimeABIParameter(name: "listRaw", type: .intptr),
                        RuntimeABIParameter(name: "element", type: .intptr),
                    ],
                    returnType: .intptr,
                    section: "Collection",
            isThrowing: false
                ),
                // ArrayDeque (STDLIB-240 / KSP-625 ring-buffer bridges)
                RuntimeABIFunctionSpec(
                    name: "__kk_arraydeque_new",
                    parameters: [],
                    returnType: .intptr,
                    section: "Collection",
                    isThrowing: false
                ),
                RuntimeABIFunctionSpec(
                    name: "__kk_arraydeque_addFirst",
                    parameters: [
                        RuntimeABIParameter(name: "dequeRaw", type: .intptr),
                        RuntimeABIParameter(name: "element", type: .intptr),
                    ],
                    returnType: .intptr,
                    section: "Collection",
                    isThrowing: false
                ),
                RuntimeABIFunctionSpec(
                    name: "__kk_arraydeque_addLast",
                    parameters: [
                        RuntimeABIParameter(name: "dequeRaw", type: .intptr),
                        RuntimeABIParameter(name: "element", type: .intptr),
                    ],
                    returnType: .intptr,
                    section: "Collection",
                    isThrowing: false
                ),
                RuntimeABIFunctionSpec(
                    name: "__kk_arraydeque_removeFirst",
                    parameters: [
                        RuntimeABIParameter(name: "dequeRaw", type: .intptr),
                    ],
                    returnType: .intptr,
                    section: "Collection",
                    isThrowing: false
                ),
                RuntimeABIFunctionSpec(
                    name: "__kk_arraydeque_removeLast",
                    parameters: [
                        RuntimeABIParameter(name: "dequeRaw", type: .intptr),
                    ],
                    returnType: .intptr,
                    section: "Collection",
                    isThrowing: false
                ),
                RuntimeABIFunctionSpec(
                    name: "__kk_arraydeque_get",
                    parameters: [
                        RuntimeABIParameter(name: "dequeRaw", type: .intptr),
                        RuntimeABIParameter(name: "index", type: .intptr),
                    ],
                    returnType: .intptr,
                    section: "Collection",
                    isThrowing: false
                ),
                RuntimeABIFunctionSpec(
                    name: "__kk_arraydeque_size",
                    parameters: [
                        RuntimeABIParameter(name: "dequeRaw", type: .intptr),
                    ],
                    returnType: .intptr,
                    section: "Collection",
                    isThrowing: false
                ),
                // STDLIB-250: Closeable.use {}
                RuntimeABIFunctionSpec(
                    name: "__kk_auto_closeable_create",
                    parameters: [
                        RuntimeABIParameter(name: "fnPtr", type: .intptr),
                        RuntimeABIParameter(name: "closureRaw", type: .intptr),
                    ],
                    returnType: .intptr,
                    section: "Collection",
                    isThrowing: false
                ),
                // STDLIB-533: List?.orEmpty()
            ])
        return functions
    }()
}
