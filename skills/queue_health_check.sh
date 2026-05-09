#!/bin/bash
# queue_health_check - Check IAMQ queue health and delivery statistics
INPUT=$(cat)
IAMQ_URL="${IAMQ_HTTP_URL:-http://host.docker.internal:18790}"
RESPONSE=$(curl -sf "$IAMQ_URL/status" 2>&1 || echo "{}")
echo "{\"result\": \"ok\", \"skill\": \"queue_health_check\", \"status\": $RESPONSE}"
