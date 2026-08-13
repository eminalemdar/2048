#!/bin/sh

# Create the DynamoDB tables the backend expects, against DynamoDB Local.
#
# DynamoDB Local starts empty, and docker-compose runs it with -inMemory, so
# the tables have to be (re)created on every `docker compose up`. Without this
# the backend returns 500 from /game/new and the leaderboard stays empty.

set -eu

ENDPOINT="${DYNAMODB_ENDPOINT:-http://dynamodb-local:8000}"
LEADERBOARD_TABLE="${DYNAMODB_TABLE:-game2048-leaderboard}"
SESSIONS_TABLE="${GAME_SESSIONS_TABLE:-game2048-sessions-dev}"

echo "Waiting for DynamoDB Local at ${ENDPOINT}..."
attempt=0
until aws dynamodb list-tables --endpoint-url "$ENDPOINT" >/dev/null 2>&1; do
    attempt=$((attempt + 1))
    if [ "$attempt" -ge 30 ]; then
        echo "ERROR: DynamoDB Local did not become ready in time" >&2
        exit 1
    fi
    sleep 1
done
echo "DynamoDB Local is ready"

# Both tables use a single string partition key named `id`, matching the item
# shape written by backend/storage.go.
create_table() {
    table_name="$1"

    if aws dynamodb describe-table \
        --table-name "$table_name" \
        --endpoint-url "$ENDPOINT" >/dev/null 2>&1; then
        echo "Table ${table_name} already exists"
        return 0
    fi

    echo "Creating table ${table_name}..."
    aws dynamodb create-table \
        --table-name "$table_name" \
        --attribute-definitions AttributeName=id,AttributeType=S \
        --key-schema AttributeName=id,KeyType=HASH \
        --billing-mode PAY_PER_REQUEST \
        --endpoint-url "$ENDPOINT" >/dev/null
    aws dynamodb wait table-exists \
        --table-name "$table_name" \
        --endpoint-url "$ENDPOINT"
    echo "Table ${table_name} created"
}

create_table "$LEADERBOARD_TABLE"
create_table "$SESSIONS_TABLE"

# saveGameSession() writes a `ttl` attribute. DynamoDB Local accepts this call
# but does not actually expire items, so this only keeps local parity with AWS.
if aws dynamodb update-time-to-live \
    --table-name "$SESSIONS_TABLE" \
    --time-to-live-specification "Enabled=true,AttributeName=ttl" \
    --endpoint-url "$ENDPOINT" >/dev/null 2>&1; then
    echo "TTL enabled on ${SESSIONS_TABLE}"
else
    echo "WARN: could not enable TTL on ${SESSIONS_TABLE} (non-fatal)"
fi

echo "DynamoDB Local initialisation complete"
