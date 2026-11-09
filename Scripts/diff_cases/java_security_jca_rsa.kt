import java.security.KeyPairGenerator
import java.security.Signature

// KUU-4438: pin JVM-compatible RSA key generation and Signature behavior.
// The generated key and signature bytes vary, so only stable properties are emitted.
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

    val modified = signed.copyOf()
    modified[0] = (modified[0].toInt() xor 1).toByte()
    verifier.initVerify(pair.getPublic())
    verifier.update(message)
    println(verifier.verify(modified))
}
