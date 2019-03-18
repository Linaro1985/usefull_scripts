#!/bin/sh

gen_pinset () {
	echo "  - address_data: ${1}"
	echo "    tls_auth_name: \"${2}\""
	echo "    tls_pubkey_pinset:"
	echo "      - digest: \"sha256\""
	echo -e "        value: \c"
	echo | openssl s_client -connect "${1}:853" 2>/dev/null |\
		openssl x509 -pubkey -noout |\
		openssl pkey -pubin -outform der |\
		openssl dgst -sha256 -binary |\
		openssl enc -base64
}

echo "resolution_type: GETDNS_RESOLUTION_STUB"
echo "round_robin_upstreams: 1"
echo "appdata_dir: \"/opt/var/lib/stubby\""
echo "tls_authentication: GETDNS_AUTHENTICATION_REQUIRED"
echo "tls_query_padding_blocksize: 256"
echo "edns_client_subnet_private: 1"
echo "idle_timeout: 10000"
echo "listen_addresses:"
echo "  - 127.0.0.1@65053"
echo "dns_transport_list:"
echo "  - GETDNS_TRANSPORT_TLS"
echo "upstream_recursive_servers:"
echo "# Google"
gen_pinset 8.8.8.8 "dns.google"
gen_pinset 8.8.4.4 "dns.google"
echo "# Cloudflare"
gen_pinset 1.1.1.1 "cloudflare-dns.com"
gen_pinset 1.0.0.1 "cloudflare-dns.com"
