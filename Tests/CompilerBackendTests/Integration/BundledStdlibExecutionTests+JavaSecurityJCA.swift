import Testing

extension BundledStdlibExecutionTests {
    /// Exercises RSA key generation, signing, verification, and in-memory
    /// KeyStore entry handling through the bundled java.security APIs.
    @Test
    func testJavaSecurityJCAContracts() throws {
        try compileAndRunKotlin(
            """
            import java.security.KeyPairGenerator
            import java.security.KeyStore
            import java.security.PublicKey
            import java.security.Signature
            import java.security.cert.Certificate

            fun main() {
                val generator = KeyPairGenerator.getInstance("RSA")
                generator.initialize(2048)
                val pair = generator.generateKeyPair()
                println(pair.getPrivate().algorithm)
                println(pair.getPrivate().format)
                println(pair.getPublic().format)

                val message = "KSwiftK JCA".encodeToByteArray()
                val signer = Signature.getInstance("SHA256withRSA")
                signer.initSign(pair.getPrivate())
                signer.update(message)
                val signed = signer.sign()

                val verifier = Signature.getInstance("SHA256withRSA")
                verifier.initVerify(pair.getPublic())
                verifier.update(message)
                println(verifier.verify(signed))
                verifier.initVerify(pair.getPublic())
                verifier.update("different".encodeToByteArray())
                println(verifier.verify(signed))

                val keyStore = KeyStore.getInstance("PKCS12")
                keyStore.load(null, null)
                val certificate = object : Certificate("X.509") {
                    override val encoded: ByteArray = byteArrayOf(1)
                    override val publicKey: PublicKey = pair.getPublic()
                }
                keyStore.setKeyEntry("jwt", pair.getPrivate(), charArrayOf('p'), arrayOf(certificate))
                println(keyStore.size())
                println(keyStore.containsAlias("JWT"))
                println(keyStore.getKey("Jwt", charArrayOf('p'))!!.algorithm)
                println(keyStore.getCertificateChain("jwt")!!.size)
                println(keyStore.aliases().nextElement())
            }
            """,
            expectedOutput: """
            RSA
            PKCS#8
            X.509
            true
            false
            1
            true
            RSA
            1
            jwt

            """
        )
    }
}
