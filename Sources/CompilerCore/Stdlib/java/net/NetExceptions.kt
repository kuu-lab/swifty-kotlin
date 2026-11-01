package java.net

import java.io.IOException

/** Thrown to indicate that there is an error creating or accessing a Socket. */
public open class SocketException : IOException {
    public constructor() : super()
    public constructor(message: String?) : super(message)
}

/** Thrown to indicate that the IP address of a host could not be determined. */
public open class UnknownHostException : IOException {
    public constructor() : super()
    public constructor(host: String?) : super(host)
}

/** Signals that an error occurred while attempting to connect a socket to a
 * remote address and port. Typically, the connection was refused remotely. */
public open class ConnectException : SocketException {
    public constructor() : super()
    public constructor(message: String?) : super(message)
}

/** Signals that an error occurred while attempting to bind a socket to a
 * local address and port. Typically, the port is in use. */
public open class BindException : SocketException {
    public constructor() : super()
    public constructor(message: String?) : super(message)
}

/** Thrown to indicate that a malformed URL has occurred. */
public open class MalformedURLException : IOException {
    public constructor() : super()
    public constructor(message: String?) : super(message)
}

/** Signals that an error occurred while attempting to connect a socket to a
 * remote address and port, but the connect timed out. */
public open class SocketTimeoutException : InterruptedIOException {
    public constructor() : super()
    public constructor(message: String?) : super(message)
}

/** Signals that an I/O operation has been interrupted. */
public open class InterruptedIOException : IOException {
    public constructor() : super()
    public constructor(message: String?) : super(message)
}

/** Thrown to indicate that there was an error in the underlying protocol. */
public open class ProtocolException : IOException {
    public constructor() : super()
    public constructor(message: String?) : super(message)
}

/** Thrown to indicate that the HTTP request could not be routed. */
public open class NoRouteToHostException : SocketException {
    public constructor() : super()
    public constructor(message: String?) : super(message)
}

/** Signals that an error occurred while attempting to determine the
 * IP address of a host: service not supported or address in use. */
public open class UnknownServiceException : IOException {
    public constructor() : super()
    public constructor(message: String?) : super(message)
}
