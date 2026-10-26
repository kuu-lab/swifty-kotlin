import Testing

extension BundledStdlibExecutionTests {
    @Test
    func testPriorityQueueComparatorOnlyConstructors() throws {
        try compileAndRunKotlin(
            try diffCaseSource("java_priority_queue_comparator_constructor.kt", file: #filePath),
            expectedOutput: "2\n2\n",
            moduleName: "KUU3484PriorityQueueComparatorConstructors"
        )
    }

    @Test(arguments: [true, false])
    func testPriorityQueueEmptyPollUsesPlatformReturn(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            try diffCaseSource("java_util_priority_queue_platform_poll.kt", file: #filePath),
            expectedOutput: "nullable-check:true\nnpe:local\nnpe:unbox\nnullable-element:null:0\n",
            moduleName: "KUU3373PriorityQueuePlatformPoll",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }

    @Test(arguments: [true, false])
    func testPriorityQueueMinimalReproducer(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            try diffCaseSource("kuu1897_priority_queue_minimal.kt", file: #filePath),
            expectedOutput: "1\n3\n",
            moduleName: "KUU1897PriorityQueueMinimal",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }

    @Test(arguments: [true, false])
    func testPriorityQueueHeapAndBoundaryContracts(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            try diffCaseSource("java_priority_queue.kt", file: #filePath),
            expectedOutput: """
            7
            -2147483648
            -2147483648
            [-2147483648, -1, 0, 1, 3, 3, 2147483647]
            true
            true
            true
            empty-remove
            empty-element
            [5, 5, 3, 2, 1]
            true
            [1, 2]
            2
            2
            9
            true
            true
            1
            7
            [a, aa, z]
            bad-capacity
            bad-capacity
            null-element
            true
            [-2147483648, 1]
            null-string
            a
            non-comparable
            true
            compare
            1
            true
            false
            [1, 2, 3, 5, 6, 7]
            true
            [1, 2, 3, 4, 5]
            6
            [1, 3, 5]
            true
            256
            true

            """,
            moduleName: "KUU1897PriorityQueueContracts",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }
}
