#!/bin/bash

# ============================================================
# Week 6 Verification — Networking and Ingress
# ============================================================

set +e

NAMESPACE="cloud-native-notes"
INGRESS_NAMESPACE="ingress-nginx"
INGRESS_CONTROLLER_DEPLOY="ingress-nginx-controller"
INGRESS_NAME="cloud-native-notes-ingress"
FRONTEND_DEPLOY="frontend"
FRONTEND_SVC="frontend"
FRONTEND_CONFIGMAP="frontend-html"
NGINX_CONFIGMAP="frontend-nginx-config"
BACKEND_SVC="backend"
BACKEND_DEPLOY="backend"
REDIS_DEPLOY="redis"

# Primary test URL ( notes.127-0-0-1.nip.io with dashes)
INGRESS_HOST="notes.127-0-0-1.nip.io"
INGRESS_URL="http://${INGRESS_HOST}"


PASS=0
FAIL=0
WARN=0

# ------------------------------------------------------------
# Helper functions
# ------------------------------------------------------------

pass() {
    echo "  ✅ PASS: $1"
    PASS=$((PASS + 1))
}

fail() {
    echo "  ❌ FAIL: $1"
    FAIL=$((FAIL + 1))
}

warn() {
    echo "  ⚠️  WARN: $1"
    WARN=$((WARN + 1))
}

section() {
    echo
    echo "============================================================"
    echo "$1"
    echo "============================================================"
    echo
}

# ------------------------------------------------------------
# 1. Basic environment
# ------------------------------------------------------------

section "1. BASIC ENVIRONMENT"

if command -v kubectl >/dev/null 2>&1; then
    pass "kubectl is installed"
else
    fail "kubectl is not installed"
fi

if kubectl cluster-info >/dev/null 2>&1; then
    pass "Kubernetes cluster is accessible"
else
    fail "Kubernetes cluster is not accessible"
fi

if command -v curl >/dev/null 2>&1; then
    pass "curl is installed"
else
    fail "curl is not installed"
fi

# ------------------------------------------------------------
# 2. Ingress Controller installed
# ------------------------------------------------------------

section "2. INGRESS CONTROLLER INSTALLED"

if kubectl get namespace "$INGRESS_NAMESPACE" >/dev/null 2>&1; then
    pass "Namespace $INGRESS_NAMESPACE exists"
else
    fail "Namespace $INGRESS_NAMESPACE does not exist"
fi

if kubectl get deployment "$INGRESS_CONTROLLER_DEPLOY" \
    -n "$INGRESS_NAMESPACE" >/dev/null 2>&1; then

    pass "Ingress controller deployment exists"

    CTRL_IMAGE=$(kubectl get deployment "$INGRESS_CONTROLLER_DEPLOY" \
        -n "$INGRESS_NAMESPACE" \
        -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null)

    echo "       Controller image: $CTRL_IMAGE"

    if echo "$CTRL_IMAGE" | grep -qi "ingress-nginx"; then
        pass "Controller image is ingress-nginx"
    else
        warn "Controller image does not look like ingress-nginx"
    fi
else
    fail "Ingress controller deployment does not exist"
fi

# IngressClass
if kubectl get ingressclass nginx >/dev/null 2>&1; then
    pass "IngressClass 'nginx' exists"
else
    fail "IngressClass 'nginx' does not exist"
fi

# ------------------------------------------------------------
# 3. Ingress Controller ready
# ------------------------------------------------------------

section "3. INGRESS CONTROLLER READY"

if kubectl get deployment "$INGRESS_CONTROLLER_DEPLOY" \
    -n "$INGRESS_NAMESPACE" >/dev/null 2>&1; then

    READY=$(kubectl get deployment "$INGRESS_CONTROLLER_DEPLOY" \
        -n "$INGRESS_NAMESPACE" \
        -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
    DESIRED=$(kubectl get deployment "$INGRESS_CONTROLLER_DEPLOY" \
        -n "$INGRESS_NAMESPACE" \
        -o jsonpath='{.spec.replicas}' 2>/dev/null)

    READY=${READY:-0}
    DESIRED=${DESIRED:-0}

    if [ "$READY" -gt 0 ] && [ "$READY" -eq "$DESIRED" ]; then
        pass "Ingress controller pods are ready ($READY/$DESIRED)"
    else
        fail "Ingress controller pods are not ready ($READY/$DESIRED)"
    fi
else
    fail "Cannot check controller readiness — deployment missing"
fi

# ------------------------------------------------------------
# 4. Ingress Controller scheduled on control plane
# ------------------------------------------------------------

section "4. INGRESS CONTROLLER ON CONTROL PLANE"

NODE=$(kubectl get pods -n "$INGRESS_NAMESPACE" \
    -l app.kubernetes.io/component=controller \
    -o jsonpath='{.items[0].spec.nodeName}' 2>/dev/null)

if [ -n "$NODE" ]; then
    echo "       Controller pod is on node: $NODE"

    if echo "$NODE" | grep -q "control-plane"; then
        pass "Ingress controller is running on the control-plane node"
    else
        fail "Ingress controller is NOT on the control-plane node (on '$NODE')"
        echo "       Patch it with:"
        echo "       kubectl patch deployment -n $INGRESS_NAMESPACE $INGRESS_CONTROLLER_DEPLOY \\"
        echo "         --type=merge \\"
        echo "         -p '{\"spec\":{\"template\":{\"spec\":{\"nodeSelector\":{\"ingress-ready\":\"true\",\"kubernetes.io/os\":\"linux\"}}}}}'"
    fi
else
    fail "Could not determine node for ingress controller pod"
fi

# Node label
if kubectl get nodes -l ingress-ready=true --no-headers 2>/dev/null | grep -q .; then
    pass "At least one node carries the ingress-ready=true label"
else
    fail "No node carries the ingress-ready=true label"
fi

# ------------------------------------------------------------
# 5. Frontend resources
# ------------------------------------------------------------

section "5. FRONTEND RESOURCES"

if kubectl get configmap "$FRONTEND_CONFIGMAP" \
    -n "$NAMESPACE" >/dev/null 2>&1; then
    pass "ConfigMap $FRONTEND_CONFIGMAP exists"

    if kubectl get configmap "$FRONTEND_CONFIGMAP" \
        -n "$NAMESPACE" -o jsonpath='{.data.index\.html}' 2>/dev/null | grep -q "Cloud Native Notes"; then
        pass "Frontend HTML contains 'Cloud Native Notes'"
    else
        fail "Frontend HTML does not contain 'Cloud Native Notes'"
    fi
else
    fail "ConfigMap $FRONTEND_CONFIGMAP does not exist"
fi

if kubectl get configmap "$NGINX_CONFIGMAP" \
    -n "$NAMESPACE" >/dev/null 2>&1; then
    pass "ConfigMap $NGINX_CONFIGMAP exists"

    if kubectl get configmap "$NGINX_CONFIGMAP" \
        -n "$NAMESPACE" -o jsonpath='{.data.default\.conf}' 2>/dev/null | grep -q "proxy_pass http://backend:3000"; then
        pass "nginx config proxies /api/ to backend:3000"
    else
        fail "nginx config does not proxy /api/ to backend:3000"
    fi
else
    fail "ConfigMap $NGINX_CONFIGMAP does not exist"
fi

if kubectl get deployment "$FRONTEND_DEPLOY" \
    -n "$NAMESPACE" >/dev/null 2>&1; then

    pass "Frontend deployment exists"

    FRONTEND_READY=$(kubectl get deployment "$FRONTEND_DEPLOY" \
        -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
    FRONTEND_DESIRED=$(kubectl get deployment "$FRONTEND_DEPLOY" \
        -n "$NAMESPACE" -o jsonpath='{.spec.replicas}' 2>/dev/null)
    FRONTEND_READY=${FRONTEND_READY:-0}
    FRONTEND_DESIRED=${FRONTEND_DESIRED:-0}

    if [ "$FRONTEND_READY" -gt 0 ] && [ "$FRONTEND_READY" -eq "$FRONTEND_DESIRED" ]; then
        pass "Frontend pods are ready ($FRONTEND_READY/$FRONTEND_DESIRED)"
    else
        fail "Frontend pods are not all ready ($FRONTEND_READY/$FRONTEND_DESIRED)"
    fi
else
    fail "Frontend deployment does not exist"
fi

if kubectl get service "$FRONTEND_SVC" \
    -n "$NAMESPACE" >/dev/null 2>&1; then
    pass "Frontend service exists"

    FPORT=$(kubectl get service "$FRONTEND_SVC" \
        -n "$NAMESPACE" -o jsonpath='{.spec.ports[0].port}' 2>/dev/null)

    if [ "$FPORT" = "80" ]; then
        pass "Frontend service exposes port 80"
    else
        fail "Frontend service exposes port $FPORT instead of 80"
    fi
else
    fail "Frontend service does not exist"
fi

# ------------------------------------------------------------
# 6. Ingress resource
# ------------------------------------------------------------

section "6. INGRESS RESOURCE"

if kubectl get ingress "$INGRESS_NAME" \
    -n "$NAMESPACE" >/dev/null 2>&1; then

    pass "Ingress $INGRESS_NAME exists"

    INGRESS_CLASS=$(kubectl get ingress "$INGRESS_NAME" \
        -n "$NAMESPACE" -o jsonpath='{.spec.ingressClassName}' 2>/dev/null)

    if [ "$INGRESS_CLASS" = "nginx" ]; then
        pass "Ingress uses ingressClassName=nginx"
    else
        fail "Ingress uses ingressClassName='$INGRESS_CLASS' (expected 'nginx')"
    fi

    INGRESS_HOST=$(kubectl get ingress "$INGRESS_NAME" \
        -n "$NAMESPACE" -o jsonpath='{.spec.rules[0].host}' 2>/dev/null)

    echo "       Ingress host: $INGRESS_HOST"

    if [ -n "$INGRESS_HOST" ]; then
        pass "Ingress has a host rule ($INGRESS_HOST)"
    else
        fail "Ingress has no host rule"
    fi

    INGRESS_PATH=$(kubectl get ingress "$INGRESS_NAME" \
        -n "$NAMESPACE" -o jsonpath='{.spec.rules[0].http.paths[0].path}' 2>/dev/null)

    if [ "$INGRESS_PATH" = "/" ]; then
        pass "Ingress path is /"
    else
        fail "Ingress path is '$INGRESS_PATH' (expected '/')"
    fi

    INGRESS_BACKEND_SVC=$(kubectl get ingress "$INGRESS_NAME" \
        -n "$NAMESPACE" -o jsonpath='{.spec.rules[0].http.paths[0].backend.service.name}' 2>/dev/null)

    if [ "$INGRESS_BACKEND_SVC" = "$FRONTEND_SVC" ]; then
        pass "Ingress routes to service '$FRONTEND_SVC'"
    else
        fail "Ingress routes to '$INGRESS_BACKEND_SVC' (expected '$FRONTEND_SVC')"
    fi

    INGRESS_BACKEND_PORT=$(kubectl get ingress "$INGRESS_NAME" \
        -n "$NAMESPACE" -o jsonpath='{.spec.rules[0].http.paths[0].backend.service.port.number}' 2>/dev/null)

    if [ "$INGRESS_BACKEND_PORT" = "80" ]; then
        pass "Ingress targets service port 80"
    else
        fail "Ingress targets service port '$INGRESS_BACKEND_PORT' (expected 80)"
    fi

    # Show events
    echo
    echo "  --- Ingress events ---"
    kubectl describe ingress "$INGRESS_NAME" -n "$NAMESPACE" \
        | sed -n '/Events:/,$p' | sed 's/^/    /'

else
    fail "Ingress $INGRESS_NAME does not exist"
fi

# ------------------------------------------------------------
# 7. Backend + Redis still healthy (dependencies)
# ------------------------------------------------------------

section "7. BACKEND AND REDIS HEALTH"

if kubectl get deployment "$BACKEND_DEPLOY" \
    -n "$NAMESPACE" >/dev/null 2>&1; then

    B_READY=$(kubectl get deployment "$BACKEND_DEPLOY" \
        -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
    B_DESIRED=$(kubectl get deployment "$BACKEND_DEPLOY" \
        -n "$NAMESPACE" -o jsonpath='{.spec.replicas}' 2>/dev/null)
    B_READY=${B_READY:-0}
    B_DESIRED=${B_DESIRED:-0}

    if [ "$B_READY" -gt 0 ] && [ "$B_READY" -eq "$B_DESIRED" ]; then
        pass "Backend pods are ready ($B_READY/$B_DESIRED)"
    else
        fail "Backend pods are not all ready ($B_READY/$B_DESIRED)"
    fi
else
    fail "Backend deployment does not exist"
fi

if kubectl get deployment "$REDIS_DEPLOY" \
    -n "$NAMESPACE" >/dev/null 2>&1; then

    R_READY=$(kubectl get deployment "$REDIS_DEPLOY" \
        -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
    R_DESIRED=$(kubectl get deployment "$REDIS_DEPLOY" \
        -n "$NAMESPACE" -o jsonpath='{.spec.replicas}' 2>/dev/null)
    R_READY=${R_READY:-0}
    R_DESIRED=${R_DESIRED:-0}

    if [ "$R_READY" -gt 0 ] && [ "$R_READY" -eq "$R_DESIRED" ]; then
        pass "Redis pods are ready ($R_READY/$R_DESIRED)"
    else
        fail "Redis pods are not all ready ($R_READY/$R_DESIRED)"
    fi
else
    fail "Redis deployment does not exist"
fi

# ------------------------------------------------------------
# 8. Ingress reachable WITHOUT port-forward
# ------------------------------------------------------------

section "8. INGRESS REACHABILITY (NO PORT-FORWARD)"

# Primary: the exact URL from the README
echo "  → Testing $INGRESS_URL ..."
if curl -fsS --max-time 5 "${INGRESS_URL}/" >/tmp/week6_index.html 2>/dev/null; then
    pass "Frontend reachable via $INGRESS_URL (no port-forward)"
else
    fail "Frontend NOT reachable via $INGRESS_URL (no port-forward)"
    echo "       Verify:"
    echo "        - Controller is on the control-plane node"
    echo "        - Docker port 80 is mapped to the control-plane container"
    echo "        - /etc/hosts not needed (nip.io resolves *.127-0-0-1.nip.io)"
fi

# Content check
if [ -f /tmp/week6_index.html ] && grep -qi "Cloud Native Notes" /tmp/week6_index.html; then
    pass "Served HTML contains 'Cloud Native Notes'"
else
    if [ -f /tmp/week6_index.html ]; then
        fail "Served HTML does not contain 'Cloud Native Notes'"
    fi
fi

# ------------------------------------------------------------
# 9. API reachable through Ingress (proxied by nginx)
# ------------------------------------------------------------

section "9. API VIA INGRESS"

if curl -fsS --max-time 5 \
    "${INGRESS_URL}/api/notes" >/tmp/week6_notes.json 2>/dev/null; then

    pass "Notes API reachable through Ingress (${INGRESS_URL}/api/notes)"

    if command -v python3 >/dev/null 2>&1; then
        if python3 - <<'PY' >/dev/null 2>&1
import json
with open("/tmp/week6_notes.json") as f:
    data = json.load(f)
assert isinstance(data, (list, dict))
PY
        then
            pass "Notes API returned valid JSON"
        else
            fail "Notes API did not return valid JSON"
        fi
    else
        warn "python3 unavailable — JSON validity not checked"
    fi

else
    fail "Notes API NOT reachable through Ingress"
    echo "       The nginx ConfigMap must proxy /api/ to http://backend:3000"
fi


# ------------------------------------------------------------
# 10. CRUD through the Ingress
# ------------------------------------------------------------

section "10. CRUD THROUGH INGRESS"

NOTE_ID=""

# --- CREATE ---
echo "  → POST /api/notes ..."
CREATE_BODY=$(curl -fsS --max-time 5 -X POST \
    "${INGRESS_URL}/api/notes" \
    -H "Content-Type: application/json" \
    -d '{"title":"Week 5 Verification","content":"Created via Ingress"}' \
    2>/dev/null)

if [ -n "$CREATE_BODY" ]; then
    if command -v python3 >/dev/null 2>&1; then
        NOTE_ID=$(echo "$CREATE_BODY" | python3 -c "import sys,json;print(json.load(sys.stdin).get('id',''))" 2>/dev/null)
    fi

    if [ -n "$NOTE_ID" ]; then
        pass "POST /api/notes created note id=$NOTE_ID"
    else
        fail "POST /api/notes did not return a note id"
        echo "       Response: $CREATE_BODY"
    fi
else
    fail "POST /api/notes failed (empty response)"
fi

# --- READ ---
if [ -n "$NOTE_ID" ]; then
    echo "  → GET /api/notes/$NOTE_ID ..."
    if curl -fsS --max-time 5 \
        "${INGRESS_URL}/api/notes/$NOTE_ID" >/tmp/week6_note.json 2>/dev/null; then
        pass "GET /api/notes/$NOTE_ID reachable"
    else
        fail "GET /api/notes/$NOTE_ID failed"
    fi

    # --- UPDATE ---
    echo "  → PUT /api/notes/$NOTE_ID ..."
    if curl -fsS --max-time 5 -X PUT \
        "${INGRESS_URL}/api/notes/$NOTE_ID" \
        -H "Content-Type: application/json" \
        -d '{"title":"Week 5 Verification (edited)","content":"Updated via Ingress"}' \
        >/tmp/week6_update.json 2>/dev/null; then

        if grep -q "edited" /tmp/week6_update.json; then
            pass "PUT /api/notes/$NOTE_ID updated the note"
        else
            fail "PUT /api/notes/$NOTE_ID did not update the note"
        fi
    else
        fail "PUT /api/notes/$NOTE_ID failed"
    fi

    # --- DELETE ---
    echo "  → DELETE /api/notes/$NOTE_ID ..."
    if curl -fsS --max-time 5 -X DELETE \
        "${INGRESS_URL}/api/notes/$NOTE_ID" \
        >/tmp/week6_delete.json 2>/dev/null; then
        pass "DELETE /api/notes/$NOTE_ID returned 200"
    else
        fail "DELETE /api/notes/$NOTE_ID failed"
    fi

    # --- CONFIRM DELETED ---
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 \
        "${INGRESS_URL}/api/notes/$NOTE_ID" 2>/dev/null)

    if [ "$HTTP_CODE" = "404" ]; then
        pass "Deleted note returns 404 (confirmed gone)"
    else
        fail "Deleted note returns HTTP $HTTP_CODE (expected 404)"
    fi
else
    warn "Skipping READ/UPDATE/DELETE — no note id from CREATE step"
fi

# ------------------------------------------------------------
# 11. Control plane routing confirmation
# ------------------------------------------------------------

section "11. CONTROL PLANE ROUTING"

CTRL_NODES=$(kubectl get nodes -l node-role.kubernetes.io/control-plane --no-headers 2>/dev/null | wc -l | tr -d ' ')
echo "       Control-plane nodes detected: $CTRL_NODES"

if [ "$CTRL_NODES" -ge 1 ]; then
    pass "Cluster has at least one control-plane node"
else
    fail "No control-plane node detected"
fi

# The controller being on the CP is what makes host port 80 work.
if [ -n "$NODE" ] && echo "$NODE" | grep -q "control-plane"; then
    pass "Ingress traffic is routed through the control-plane node"
else
    fail "Ingress is NOT routed through the control-plane node"
fi

# Check the controller service — NodePort must be assigned
CTRL_SVC_TYPE=$(kubectl get svc "$INGRESS_CONTROLLER_DEPLOY" \
    -n "$INGRESS_NAMESPACE" -o jsonpath='{.spec.type}' 2>/dev/null)
CTRL_NODEPORT=$(kubectl get svc "$INGRESS_CONTROLLER_DEPLOY" \
    -n "$INGRESS_NAMESPACE" -o jsonpath='{.spec.ports[?(@.port==80)].nodePort}' 2>/dev/null)

echo "       Controller Service type: $CTRL_SVC_TYPE"
echo "       Controller NodePort (port 80 → nodePort): $CTRL_NODEPORT"

if [ -n "$CTRL_NODEPORT" ]; then
    pass "Controller Service has a NodePort allocated ($CTRL_NODEPORT)"
else
    warn "Could not determine controller NodePort"
fi


# ------------------------------------------------------------
# FINAL SCORE
# ------------------------------------------------------------

echo
echo "=========================================="
echo "          VERIFICATION SUMMARY"
echo "=========================================="
echo

echo "Passed checks : $PASS"
echo "Failed checks : $FAIL"
echo "Warnings      : $WARN"

TOTAL=$((PASS + FAIL))

if [ "$TOTAL" -gt 0 ]; then
    SCORE=$((PASS * 100 / TOTAL))
else
    SCORE=0
fi

echo "Verification score: $SCORE%"
echo

if [ "$FAIL" -eq 0 ]; then

    echo "🎉 WEEK 6 VERIFICATION PASSED!"
    echo
    echo "All automatically verifiable Week 6 tasks"
    echo "have been successfully verified."

else

    echo "⚠️ WEEK 6 VERIFICATION INCOMPLETE"
    echo
    echo "Fix the failed checks and run the script again."

fi

echo
echo "=========================================="

rm -f /tmp/week6_index.html
rm -f /tmp/week6_notes.json
rm -f /tmp/week6_health.json
rm -f /tmp/week6_note.json
rm -f /tmp/week6_update.json
rm -f /tmp/week6_delete.json

if [ "$FAIL" -gt 0 ]; then
    exit 1
else
    exit 0
fi
