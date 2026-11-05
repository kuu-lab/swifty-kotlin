package java.security

// JDK java.security.DigestException — thrown by
// MessageDigest.digest(byte[], int, int) when the requested length is below
// digestLength or the offset/length pair cannot hold the digest in the
// output buffer.
public open class DigestException : java.lang.Exception {
    public constructor() : super()

    public constructor(message: String?) : super(message)

    public constructor(message: String?, cause: Throwable?) : super(message, cause)

    public constructor(cause: Throwable?) : super(cause)
}
