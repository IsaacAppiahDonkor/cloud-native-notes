#!/usr/bin/env bash
set -u

# ============================================================
# Week 3 - Kubernetes Core Objects
# ============================================================

IMAGE="cloud-native-notes:2.0"
NAMESPACE="cloud-native-notes"
DEPLOYMENT="backend"
SERVICE="backend"
EXPECTED_REPLICAS="2"
EXTRA_REPLICAS="4"
APP_PORT="3000"


PASS=0
FAIL=0
WARN=0
SCORE=0
TOTAL_POINTS=100

DEPLOYMENT_IMAGE=""
DESIRED_REPLICAS=""
READY_COUNT=0
PORT_FORWARD_OK=false

POST_RESPONSE="/tmp/week3_post_response"
GET_RESPONSE="/tmp/week3_get_response"
HEALTH_RESPONSE="/tmp/week3_health_response"

cleanup() {
    rm -f "$POST_RESPONSE" "$GET_RESPONSE" "$HEALTH_RESPONSE"
}
trap cleanup EXIT

# ------------------------------------------------------------
# Helper functions
# ------------------------------------------------------------

pass() {
    echo "  [PASS] $1"
    PASS=$((PASS + 1))
}

fail() {
    echo "  [FAIL] $1"
    FAIL=$((FAIL + 1))
}

warn() {
    echo "  [WARN] $1"
    WARN=$((WARN + 1))
}

info() {
    echo "  [INFO] $1"
}

points() {
    SCORE=$((SCORE + $1))
}

section() {
    echo
    echo "============================================================"
    echo "$1"
    echo "============================================================"
}

# ============================================================
# 1. Kubernetes / kubectl
# ============================================================

section "1. Kubernetes / kubectl"

if ! command -v kubectl >/dev/null 2>&1; then
    fail "kubectl is not installed or not available in PATH"
    echo
    echo "Cannot continue Kubernetes verification."
    exit 1
else
    pass "kubectl is installed"
    points 5
fi

if kubectl cluster-info >/dev/null 2>&1; then
    pass "Kubernetes cluster is reachable"
else
    fail "Kubernetes cluster is not reachable"
    echo
    echo "Check your current context with:"
    echo "  kubectl config current-context"
    echo
    echo "Check available contexts with:"
    echo "  kubectl config get-contexts"
    exit 1
fi

echo
echo "  Current Kubernetes context:"
kubectl config current-context

# ============================================================
# 2. Docker image
# ============================================================

section "2. Build the Week 3 Image"

if ! command -v docker >/dev/null 2>&1; then
    fail "Docker is not installed"
else
    if docker image inspect "$IMAGE" >/dev/null 2>&1; then
        pass "Image '$IMAGE' exists locally"
        points 15

        IMAGE_ID=$(docker image inspect "$IMAGE" \
            --format '{{.Id}}' 2>/dev/null)
        IMAGE_SIZE=$(docker image inspect "$IMAGE" \
            --format '{{.Size}}' 2>/dev/null)

        echo "       Image ID  : $IMAGE_ID"
        echo "       Image size: $IMAGE_SIZE bytes"
    else
        fail "Image '$IMAGE' was not found locally"
        echo
        echo "Expected image:"
        echo "  $IMAGE"
        echo
        echo "You should have built it with:"
        echo "  docker build -t cloud-native-notes:2.0 ./backend"
    fi
fi

# ============================================================
# 3. Load image into Kind
# ============================================================

section "3. Load the Image to Kind"

if ! command -v docker >/dev/null 2>&1; then
    fail "Docker is required to verify the Kind image"
else
    NODE_NAMES=$(kubectl get nodes \
        -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' \
        2>/dev/null)

    KIND_IMAGE_FOUND=false

    if [[ -z "$NODE_NAMES" ]]; then
        fail "Could not determine Kubernetes node names"
    else
        while IFS= read -r NODE_NAME; do
            [[ -z "$NODE_NAME" ]] && continue

            if docker exec "$NODE_NAME" crictl images 2>/dev/null | \
                awk -v image="$IMAGE" '
                    BEGIN {
                        # Split "cloud-native-notes:2.0" into repo and tag
                        n = split(image, parts, ":")
                        repo = parts[1]
                        tag  = (n > 1) ? parts[2] : "latest"
                    }
                    NR > 1 {
                        # crictl $1 is repo (may have registry prefix), $2 is tag
                        # Match if repo ends with our repo name and tag matches
                        if ($2 == tag && $1 ~ ("(^|/)" repo "$")) {
                            found = 1
                        }
                    }
                    END { exit(found ? 0 : 1) }
                '; then
                KIND_IMAGE_FOUND=true
                echo "       Found $IMAGE on Kind node: $NODE_NAME"
            fi


        done <<< "$NODE_NAMES"

        if [[ "$KIND_IMAGE_FOUND" == true ]]; then
            pass "Image '$IMAGE' is loaded into Kind"
            points 10
        else
            fail "Image '$IMAGE' was not found in the Kind node image stores"
            echo
            echo "You should load it with:"
            echo "  kind load docker-image $IMAGE --name <YOUR-BOOTCAMP-CLUSTER-NAME>"
        fi
    fi
fi

# ============================================================
# 4. Namespace
# ============================================================

section "4. Kubernetes Namespace"

if kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
    pass "Namespace '$NAMESPACE' exists"
    points 10
else
    fail "Namespace '$NAMESPACE' does not exist"
    echo
    echo "You should deploy the Kubernetes objects"
    echo "using the manifests in k8s/."
fi

# ============================================================
# 5. Backend Deployment
# 15 points
#
# 5 points - Deployment exists
# 5 points - Correct Week 3 image
# 5 points - 2 replicas
# ============================================================

section "5. Backend Deployment"

if ! kubectl get deployment "$DEPLOYMENT" \
    -n "$NAMESPACE" >/dev/null 2>&1; then

    fail "Deployment '$DEPLOYMENT' was not found"
else
    pass "Deployment '$DEPLOYMENT' exists"
    points 5

    DEPLOYMENT_IMAGE=$(kubectl get deployment "$DEPLOYMENT" \
        -n "$NAMESPACE" \
        -o jsonpath='{.spec.template.spec.containers[0].image}' \
        2>/dev/null)

    DESIRED_REPLICAS=$(kubectl get deployment "$DEPLOYMENT" \
        -n "$NAMESPACE" \
        -o jsonpath='{.spec.replicas}' 2>/dev/null)

    echo "       Deployment image: ${DEPLOYMENT_IMAGE:-unknown}"
    echo "       Desired replicas: ${DESIRED_REPLICAS:-unknown}"

    if [[ "$DEPLOYMENT_IMAGE" == "$IMAGE" ]]; then
        pass "Deployment uses '$IMAGE'"
        points 5
    else
        fail "Deployment does not use the expected Week 3 image"
        echo "       Expected: $IMAGE"
        echo "       Found   : ${DEPLOYMENT_IMAGE:-unknown}"
    fi

    if [[ "$DESIRED_REPLICAS" == "$EXPECTED_REPLICAS" ]]; then
        pass "Deployment has 2 replicas"
        points 5
    else
        fail "Deployment has ${DESIRED_REPLICAS:-unknown} replicas instead of 2"
    fi
fi

# ============================================================
# 6. Backend Pods
# 15 points
#
# 5 points - Pods exist
# 10 points - Both expected pods are Ready
# ============================================================

section "6. Backend Pods"

POD_COUNT=$(kubectl get pods \
    -n "$NAMESPACE" \
    -l app="$DEPLOYMENT" \
    --no-headers 2>/dev/null | wc -l)

READY_COUNT=$(kubectl get pods \
    -n "$NAMESPACE" \
    -l app="$DEPLOYMENT" \
    --no-headers 2>/dev/null | \
    awk '$2 ~ /^[0-9]+\/[0-9]+$/ {
        split($2,a,"/")
        if (a[1] == a[2]) count++
    }
    END {print count+0}')

if [[ "$POD_COUNT" -gt 0 ]]; then
    pass "Backend pods exist"
    points 5

    echo
    echo "       Pods:"
    kubectl get pods -n "$NAMESPACE" -l app="$DEPLOYMENT"
else
    fail "No backend pods were found"
fi

if [[ "$READY_COUNT" -eq "$EXPECTED_REPLICAS" ]]; then
    pass "All 2 backend pods are Ready"
    points 10
elif [[ "$READY_COUNT" -gt 0 ]]; then
    fail "$READY_COUNT of 2 backend pods are Ready"
else
    fail "No backend pods are Ready"
fi

# ============================================================
# 7. Backend Service
# 10 points
#
# 5 points - Service exists
# 5 points - 3000 -> 3000
# ============================================================

section "7. Backend Service"

if kubectl get service "$SERVICE" \
    -n "$NAMESPACE" >/dev/null 2>&1; then

    pass "Service '$SERVICE' exists"
    points 5

    SERVICE_TYPE=$(kubectl get service "$SERVICE" \
        -n "$NAMESPACE" \
        -o jsonpath='{.spec.type}' 2>/dev/null)

    SERVICE_PORT=$(kubectl get service "$SERVICE" \
        -n "$NAMESPACE" \
        -o jsonpath='{.spec.ports[0].port}' 2>/dev/null)

    TARGET_PORT=$(kubectl get service "$SERVICE" \
        -n "$NAMESPACE" \
        -o jsonpath='{.spec.ports[0].targetPort}' 2>/dev/null)

    echo "       Type       : $SERVICE_TYPE"
    echo "       Port       : $SERVICE_PORT"
    echo "       Target port: $TARGET_PORT"

    if [[ "$SERVICE_PORT" == "3000" ]] && \
       [[ "$TARGET_PORT" == "3000" ]]; then
        pass "Service exposes port 3000 -> 3000"
        points 5
    else
        fail "Service does not expose the expected 3000 -> 3000 mapping"
    fi
else
    fail "Service '$SERVICE' was not found"
fi

# Informational endpoint check; not separately scored.
section "7a. Service Endpoints"

ENDPOINTS=$(kubectl get endpoints "$SERVICE" \
    -n "$NAMESPACE" \
    -o jsonpath='{.subsets[*].addresses[*].ip}' \
    2>/dev/null)

if [[ -n "$ENDPOINTS" ]]; then
    info "Backend service has active endpoints"
    echo "       Endpoint IPs: $ENDPOINTS"
else
    warn "Backend service has no active endpoints"
    echo
    echo "This usually means the Service selector does not"
    echo "match the backend pods, or the pods are not Ready."
fi

# ============================================================
# 8. Port forwarding
# 5 points
#
# The verifier does not create the port-forward.
# The learner should run:
#   kubectl port-forward -n cloud-native-notes svc/backend 3000:3000
# ============================================================

section "8. Port Forward the Service"

if ! command -v curl >/dev/null 2>&1; then
    fail "curl is not installed; port-forward cannot be verified"
else
    if curl -fsS --max-time 3 \
        "http://localhost:$APP_PORT/health" \
        >/dev/null 2>&1; then

        PORT_FORWARD_OK=true
        pass "Backend service is accessible through localhost:$APP_PORT"
        points 5
    else
        fail "No working port-forward detected on localhost:$APP_PORT"
        echo
        echo "You should run:"
        echo "  kubectl port-forward -n $NAMESPACE svc/$SERVICE $APP_PORT:$APP_PORT"
    fi
fi

# ============================================================
# 9. Post messages
# 10 points
#
# The verifier posts one verification note to confirm that the
# learner's backend accepts POST /api/notes.
# ============================================================

section "9. Post Messages to the Backend"

POST_STATUS=$(curl -sS \
    --max-time 5 \
    -o "$POST_RESPONSE" \
    -w '%{http_code}' \
    -X POST \
    "http://localhost:$APP_PORT/api/notes" \
    -H "Content-Type: application/json" \
    -d '{"title":"Week 3 Verification","content":"Kubernetes Core Objects"}' \
    2>/dev/null || true)

if [[ "$POST_STATUS" == "200" || "$POST_STATUS" == "201" ]]; then
    pass "Backend accepted a POST request to /api/notes"
    points 10

    echo
    echo "       HTTP status: $POST_STATUS"
    echo "       Response:"
    sed 's/^/       /' "$POST_RESPONSE"
elif [[ "$PORT_FORWARD_OK" != true ]]; then
    fail "Could not post a message because the service is not accessible"
    echo "       Expected a working port-forward on localhost:$APP_PORT"
else
    fail "POST /api/notes returned HTTP $POST_STATUS"
    echo
    echo "       Response:"
    sed 's/^/       /' "$POST_RESPONSE"
fi

# ============================================================
# 10. Test the application
# 5 points
#
# Verify both endpoints described in the Solution Guide:
#   GET /api/notes
#   GET /health
# ============================================================

section "10. Test the Application"

GET_STATUS=$(curl -sS \
    --max-time 5 \
    -o "$GET_RESPONSE" \
    -w '%{http_code}' \
    "http://localhost:$APP_PORT/api/notes" \
    2>/dev/null || true)

HEALTH_STATUS=$(curl -sS \
    --max-time 5 \
    -o "$HEALTH_RESPONSE" \
    -w '%{http_code}' \
    "http://localhost:$APP_PORT/health" \
    2>/dev/null || true)

GET_OK=false
HEALTH_OK=false

if [[ "$GET_STATUS" == "200" ]]; then
    GET_OK=true
    pass "GET /api/notes returned HTTP 200"
else
    fail "GET /api/notes returned HTTP ${GET_STATUS:-unknown}"
fi

if [[ "$HEALTH_STATUS" == "200" ]]; then
    HEALTH_OK=true
    pass "GET /health returned HTTP 200"
else
    fail "GET /health returned HTTP ${HEALTH_STATUS:-unknown}"
fi

if [[ "$GET_OK" == true && "$HEALTH_OK" == true ]]; then
    points 5
fi

echo
echo "       /api/notes response:"
if [[ -s "$GET_RESPONSE" ]]; then
    sed 's/^/       /' "$GET_RESPONSE"
else
    echo "       <no response>"
fi

echo
echo "       /health response:"
if [[ -s "$HEALTH_RESPONSE" ]]; then
    sed 's/^/       /' "$HEALTH_RESPONSE"
else
    echo "       <no response>"
fi

# ============================================================
# EXTRA CHALLENGES - NOT GRADED
# ============================================================

section "Extra Challenges"

EXTRA_REGISTRY=false
EXTRA_REPLICAS_DONE=false
EXTRA_READY=false

if [[ -n "$DEPLOYMENT_IMAGE" ]] && [[ "$DEPLOYMENT_IMAGE" == */* ]]; then
    EXTRA_REGISTRY=true
    echo "  🏆 Registry challenge detected!"
    echo "     Deployment image: $DEPLOYMENT_IMAGE"
else
    echo "  💡 Registry challenge:"
    echo "     Push cloud-native-notes:2.0 to Docker Hub or another"
    echo "     registry, then update the Deployment to use that image."
fi

if [[ "$DESIRED_REPLICAS" == "$EXTRA_REPLICAS" ]]; then
    EXTRA_REPLICAS_DONE=true
    echo
    echo "  🚀 Scaling challenge detected!"
    echo "     Deployment has been changed to 4 replicas."
else
    echo
    echo "  💡 Scaling challenge:"
    echo "     Change the backend Deployment from 2 to 4 replicas."
fi

if [[ "$READY_COUNT" -eq "$EXTRA_REPLICAS" ]]; then
    EXTRA_READY=true
    echo
    echo "  🎯 All 4 backend pods are Ready!"
fi

echo

if [[ "$EXTRA_REGISTRY" == true && \
      "$EXTRA_REPLICAS_DONE" == true && \
      "$EXTRA_READY" == true ]]; then

    echo "  🏆 EXTRA CHALLENGE COMPLETE!"
    echo
    echo "  You went beyond the core requirements."
    echo "  Great job exploring Kubernetes further!"
    echo
    echo '  "The fastest way to become comfortable with'
    echo '   Kubernetes is to keep experimenting."'

elif [[ "$EXTRA_REGISTRY" == true || \
        "$EXTRA_REPLICAS_DONE" == true ]]; then

    echo "  🌟 NICE WORK!"
    echo
    echo "  You have started working on the extra challenge."
    echo "  Keep experimenting and see if you can complete it!"
    echo
    echo '  "Small experiments build big engineering skills."'

else

    echo "  💡 OPTIONAL EXTRA CHALLENGE"
    echo
    echo "  The extra challenges are not part of your grade."
    echo "  When you're ready, try using a registry image"
    echo "  and scaling the backend to 4 replicas."
    echo
    echo '  "Every extra challenge is another opportunity'
    echo '   to learn something new."'
fi

# ============================================================
# Informational resource section
# ============================================================

section "11. Deployment Resources"

RESOURCE_REQUESTS=$(kubectl get deployment "$DEPLOYMENT" \
    -n "$NAMESPACE" \
    -o jsonpath='{.spec.template.spec.containers[0].resources.requests}' \
    2>/dev/null)

RESOURCE_LIMITS=$(kubectl get deployment "$DEPLOYMENT" \
    -n "$NAMESPACE" \
    -o jsonpath='{.spec.template.spec.containers[0].resources.limits}' \
    2>/dev/null)

if [[ -n "$RESOURCE_REQUESTS" || -n "$RESOURCE_LIMITS" ]]; then
    info "Deployment contains resource requests/limits"
    echo "       Requests: ${RESOURCE_REQUESTS:-none}"
    echo "       Limits  : ${RESOURCE_LIMITS:-none}"
else
    info "No resource requests or limits detected"
fi

echo
info "Resource configuration is reported but is not scored."

# ============================================================
# FINAL SCORE
# ============================================================

echo
echo "=========================================="
echo "        WEEK 3 VERIFICATION SUMMARY"
echo "=========================================="
echo

echo "Passed checks : $PASS"
echo "Failed checks : $FAIL"
echo "Warnings      : $WARN"

echo
echo "Score: $SCORE/$TOTAL_POINTS"
echo "Grade: $SCORE%"
echo

if [[ "$FAIL" -eq 0 ]]; then
    echo "🎉 WEEK 3 VERIFICATION PASSED!"
    echo
    echo "All automatically verifiable Week 3"
    echo "core requirements have been successfully completed."
else
    echo "⚠️ WEEK 3 VERIFICATION INCOMPLETE"
    echo
    echo "Some required core tasks have not been verified."
    echo "Fix the failed checks and run the script again."
fi

echo
echo "=========================================="

# Extra challenges never affect the grade or exit status.
exit "$FAIL"
