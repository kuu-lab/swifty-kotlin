private let abi = RuntimeABISectionBuilder("JavaNet")
private let abiAwt = RuntimeABISectionBuilder("Awt")

public extension RuntimeABISpec {
    /// Runtime bridges for the bundled `java.net` compatibility layer
    /// (InetAddress/DNS, Socket/ServerSocket over POSIX sockets, URL and
    /// URLConnection over Foundation/file I/O) and the small AWT support
    /// surface (headless detection and pointer location for MouseInfo).
    static let javaNetFunctions: [RuntimeABIFunctionSpec] = [
        // DNS / InetAddress
        abi.th("__kk_net_resolve", "hostRaw outThrown"),
        abi.nt("__kk_net_reverse_lookup", "addressRaw"),
        abi.nt("__kk_net_local_host_name"),
        // Socket
        abi.nt("__kk_net_socket_create"),
        abi.th("__kk_net_socket_connect", "boxRaw hostRaw port timeoutMillis outThrown", ret: .void),
        abi.th("__kk_net_socket_bind", "boxRaw hostRaw port outThrown", ret: .void),
        abi.th("__kk_net_socket_input_stream", "boxRaw outThrown"),
        abi.th("__kk_net_socket_output_stream", "boxRaw outThrown"),
        abi.nt("__kk_net_socket_close", "boxRaw", ret: .void),
        abi.nt("__kk_net_socket_is_closed", "boxRaw", raw: true),
        abi.nt("__kk_net_socket_is_connected", "boxRaw", raw: true),
        abi.nt("__kk_net_socket_is_bound", "boxRaw", raw: true),
        abi.nt("__kk_net_socket_remote_address", "boxRaw"),
        abi.nt("__kk_net_socket_remote_port", "boxRaw"),
        abi.nt("__kk_net_socket_local_address", "boxRaw"),
        abi.nt("__kk_net_socket_local_port", "boxRaw"),
        abi.nt("__kk_net_socket_get_option", "boxRaw option"),
        abi.nt("__kk_net_socket_set_option", "boxRaw option value", ret: .void),
        abi.nt("__kk_net_socket_shutdown", "boxRaw how", ret: .void),
        abi.nt("__kk_net_socket_is_input_shutdown", "boxRaw", raw: true),
        abi.nt("__kk_net_socket_is_output_shutdown", "boxRaw", raw: true),
        // ServerSocket
        abi.nt("__kk_net_server_socket_create"),
        abi.th("__kk_net_server_socket_bind", "boxRaw hostRaw port backlog outThrown", ret: .void),
        abi.th("__kk_net_server_socket_accept", "boxRaw outThrown"),
        abi.nt("__kk_net_server_socket_close", "boxRaw", ret: .void),
        abi.nt("__kk_net_server_socket_is_closed", "boxRaw", raw: true),
        abi.nt("__kk_net_server_socket_is_bound", "boxRaw", raw: true),
        abi.nt("__kk_net_server_socket_local_port", "boxRaw"),
        abi.nt("__kk_net_server_socket_local_address", "boxRaw"),
        abi.nt("__kk_net_server_socket_get_timeout", "boxRaw"),
        abi.nt("__kk_net_server_socket_set_timeout", "boxRaw timeoutMillis", ret: .void),
        abi.nt("__kk_net_server_socket_get_reuse_address", "boxRaw"),
        abi.nt("__kk_net_server_socket_set_reuse_address", "boxRaw value", ret: .void),
        // URL / URLConnection
        abi.th("__kk_net_url_open_stream", "specRaw outThrown"),
        abi.nt("__kk_net_url_connection_new", "specRaw"),
        abi.nt("__kk_net_url_connection_set_method", "boxRaw methodRaw", ret: .void),
        abi.nt("__kk_net_url_connection_set_do_output", "boxRaw value", ret: .void),
        abi.th("__kk_net_url_connection_connect", "boxRaw headersRaw connectTimeoutMs readTimeoutMs outThrown", ret: .void),
        abi.th("__kk_net_url_connection_input_stream", "boxRaw outThrown"),
        abi.th("__kk_net_url_connection_output_stream", "boxRaw outThrown"),
        abi.nt("__kk_net_url_connection_body_text", "boxRaw"),
        abi.nt("__kk_net_url_connection_header", "boxRaw nameRaw"),
        abi.nt("__kk_net_url_connection_header_long", "boxRaw nameRaw"),
        abi.nt("__kk_net_url_connection_header_at", "boxRaw index"),
        abi.nt("__kk_net_url_connection_header_key_at", "boxRaw index"),
        abi.nt("__kk_net_url_connection_headers_map", "boxRaw"),
        abi.nt("__kk_net_url_connection_response_code", "boxRaw"),
        abi.nt("__kk_net_url_connection_response_message", "boxRaw"),
        abi.nt("__kk_net_url_connection_disconnect", "boxRaw", ret: .void),
        // AWT environment
        abiAwt.nt("__kk_awt_is_headless", raw: true),
        abiAwt.th("__kk_awt_pointer_location", "outThrown"),
    ]
}
