#!/bin/sh

echo "/ip dns static" > adblock_dns.rsc
curl -s https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts | grep -Po "^0.0.0.0 \K[^ ]*" | sort -u | grep . | sed "s/^/add address=127.0.0.1 name=/" >> adblock_dns.rsc

