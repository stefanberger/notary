#!/usr/bin/env bash

/docker-entrypoint.sh /opt/couchdb/bin/couchdb &

if [ -n "$COUCHDB_USER" ] && [ -n "$COUCHDB_PASSWORD" ]; then
	pass="${COUCHDB_USER}:${COUCHDB_PASSWORD}@"
fi

COUCHDB_URL=${COUCHDB_URL:-https://${pass}127.0.0.1:6984}

if [[ "${COUCHDB_URL}" =~ ^([a-z]+)://(([^:]+):([^@]+)@)?([^:]+)(:([0-9]+))?(/.*)?$ ]]; then

	scheme="${BASH_REMATCH[1]}"
	case "$scheme" in
	http|https) ;;
	*) echo "Bad URL scheme $scheme." >&2 ;;
	esac

	host="${BASH_REMATCH[5]}"

	port="${BASH_REMATCH[7]}"
	case "$port" in
	[0-9]+) ;;
	"")	case "$scheme" in
		http) port=80;;
		https) port=443;;
		esac
	esac
else
	echo "Invalid URL '$COUCHDB_URL'." >&2
	exit 1
fi

while :; do
	bash -c "exec 100<>/dev/tcp/${host}/${port}" &>/dev/null
	[ $? -eq 0 ] && break
	sleep 0.5
done

CURL='curl -k -s
    -H "Accept: application/json"
    -H "Content-Type: application/json"'

for db in "_global_changes" "_replicator" "_users"; do
    if [ -n "$($CURL -XGET ${COUCHDB_URL}/${db} | grep "error" | grep "reason")" ];
    then
	$CURL -XPUT ${COUCHDB_URL}/${db}
    fi
done

if [ -n "$($CURL -XGET ${COUCHDB_URL}/_users/org.couchdb.user:$SERVER_USER |
           grep "error" | grep "reason")" ];
then
    $CURL -XPUT ${COUCHDB_URL}/_users/org.couchdb.user:$SERVER_USER \
        -d '{"name": "'$SERVER_USER'", "password": "'$SERVER_USER_PASSWORD'", "roles": [], "type": "user"}'
fi

if [ -n "$($CURL -XGET ${COUCHDB_URL}/_users/org.couchdb.user:$SIGNER_USER |
           grep "error" | grep "reason")" ];
then
    $CURL -XPUT ${COUCHDB_URL}/_users/org.couchdb.user:$SIGNER_USER \
        -d '{"name": "'$SIGNER_USER'", "password": "'$SIGNER_USER_PASSWORD'", "roles": [], "type": "user"}'
fi

for db in "notaryserver\$tuf_files" "notaryserver\$changefeed";
do
    if [ -n "$($CURL -XGET ${COUCHDB_URL}/${db} | grep "error" | grep "reason")" ];
    then
        $CURL -XPUT ${COUCHDB_URL}/${db}

        $CURL -XPUT ${COUCHDB_URL}/${db}/_security \
            -d '{"admins":{"names":["'$SERVER_USER'"],"roles":["admins"]}}'
    fi
done

for db in "notarysigner\$private_keys"
do
    if [ -n "$($CURL -XGET ${COUCHDB_URL}/${db} | grep "error" | grep "reason")" ];
    then
        $CURL -XPUT ${COUCHDB_URL}/${db}

        $CURL -XPUT ${COUCHDB_URL}/${db}/_security \
            -d '{"admins":{"names":["'$SIGNER_USER'"],"roles":["admins"]}}'
    fi
done

wait
