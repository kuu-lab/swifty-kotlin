import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [true, false])
    func testByteStringImplicitBuilderLiteralContracts(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            try diffCaseSource("kotlinx_io_bytestring_implicit_literals.kt", file: #filePath),
            expectedOutput: "0102032a\n8004\n80ffff7f\n",
            moduleName: "KUU1760ByteStringImplicitLiterals",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }

    @Test(arguments: [true, false])
    func testByteStringConstructorUnsafeAndAppendableContracts(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            try diffCaseSource("kotlinx_io_bytestring_api_supplements.kt", file: #filePath),
            expectedOutput: "start-only:0203\nend-only:0102:1\nend-default:0203:2\n"
                + "constructor-neg:IOOB\nconstructor-high:IOOB\nconstructor-reversed:IAE\n"
                + "constructor-both-neg:IAE\nconstructor-both-high:IAE\nconstructor-equal-high:IOOB\n"
                + "unsafe-read-only-identity:true:0102\nunsafe-throw:1\nunsafe-nlr:7\n"
                + "appendable-identity:true:AA==\nunsigned-factory:80ff\n"
                + "order-less:true\norder-unsigned:true\nhex-cr:0102\nhex-range:IOOB\n",
            moduleName: "KUU1760ByteStringApiSupplements",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }

    @Test(arguments: [true, false])
    func testByteStringBuilderDefaultsExtensionsAndUnsafeContract(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            try diffCaseSource("kotlinx_io_bytestring_builder_contracts.kt", file: #filePath),
            expectedOutput: "0102038004050607\n01\nfull-capacity-shares:true\n"
                + "old-after-append:0102\nnew-after-append:010203\ncallbacks:1\n",
            moduleName: "KUU1760ByteStringBuilderContracts",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }

    @Test(arguments: [true, false])
    func testByteStringCodecBoundsPaddingAndHexContracts(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            try diffCaseSource("kotlinx_io_bytestring_codec_contracts.kt", file: #filePath),
            expectedOutput: "encode-start:IllegalArgumentException\ndecode-string-start:IllegalArgumentException\n"
                + "decode-array-start:IllegalArgumentException\nnegative-before-reversed:IndexOutOfBoundsException\n"
                + "outside-before-reversed:IndexOutOfBoundsException\npad-bits-two:IllegalArgumentException\n"
                + "pad-bits-three:IllegalArgumentException\npad-bits-absent:IllegalArgumentException\n"
                + "zero-pad-bits:0000\nchar-sequence:00\n00:01|02\n03:04|05\n06\n01:02|03\n04:05|06\n"
                + "00010203040506\n00010203040506\nfullwidth-digits:NumberFormatException\n"
                + "fullwidth-letters:NumberFormatException\nfullwidth-number:NumberFormatException\n",
            moduleName: "KUU1760ByteStringCodecContracts",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }

    @Test(arguments: [true, false])
    func testByteStringDecodeDestinationAndHexLengthContracts(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            try diffCaseSource("kotlinx_io_bytestring_decode_destination.kt", file: #filePath),
            expectedOutput: "IOOB\ninvalid-symbol\n000000090909\n"
                + "mime-single:IllegalArgumentException\npem-single:IllegalArgumentException\n"
                + "mime-double:0\nhex-length:IllegalArgumentException\n",
            moduleName: "KUU1760ByteStringDecodeDestination",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }
}
