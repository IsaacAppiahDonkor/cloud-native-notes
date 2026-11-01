#!/bin/bash

# ============================================================
# Week 5 Verification — Troubleshooting with kubectl
# (core exercise + crashloop bonus only)
# ============================================================

set +e

NAMESPACE="cloud-native-notes"
BROKEN_POD_NAME="broken-image-pod"

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
# Section 1 — deliberately broken pod (core exercise)
# ------------------------------------------------------------

section "1. DELIBERATELY BROKEN POD"

if kubectl get pod "$BROKEN_POD_NAME" -n "$NAMESPACE" >/dev/null 2>&1; then
    pass "Pod $BROKEN_POD_NAME exists"
else
    fail "Pod $BROKEN_POD_NAME does not exist"
    echo "       Create it to pass this exercise"

fi

if kubectl get pod "$BROKEN_POD_NAME" -n "$NAMESPACE" >/dev/null 2>&1; then

    # --- STATUS column (kubectl get) ---
    B_STATUS=$(kubectl get pod "$BROKEN_POD_NAME" -n "$NAMESPACE" \
        --no-headers 2>/dev/null | awk '{print $3}')
    B_REASON=$(kubectl get pod "$BROKEN_POD_NAME" -n "$NAMESPACE" \
        -o jsonpath='{.status.containerStatuses[0].state.waiting.reason}' 2>/dev/null)

    echo "       STATUS column       : $B_STATUS"
    echo "       Waiting.reason      : ${B_REASON:-<none>}"

    if [ "$B_STATUS" = "ImagePullBackOff" ] || \
       [ "$B_STATUS" = "ErrImagePull" ] || \
       [ "$B_REASON" = "ImagePullBackOff" ] || \
       [ "$B_REASON" = "ErrImagePull" ]; then
        pass "Broken pod is in ImagePullBackOff/ErrImagePull"
    else
        fail "Broken pod is not in an image-pull failure state (STATUS=$B_STATUS reason=$B_REASON)"
    fi

    # --- kubectl describe reveals the specific error ---
    B_DESC=$(kubectl describe pod "$BROKEN_POD_NAME" -n "$NAMESPACE" 2>/dev/null)
    if echo "$B_DESC" | grep -qE 'Failed to pull image|ErrImagePull|pull access denied|manifest unknown|not found'; then
        pass "kubectl describe shows the pull failure message"
        echo "       Excerpt:"
        echo "$B_DESC" | grep -E 'Failed to pull image|ErrImagePull|pull access|manifest unknown' \
            | head -2 | sed 's/^/         /'
    else
        fail "kubectl describe does not show a pull-failure message"
    fi

    # --- describe output must contain the Events section ---
    if echo "$B_DESC" | grep -q "^Events:"; then
        pass "kubectl describe output includes an Events section"
    else
        fail "kubectl describe output has no Events section"
    fi

    # --- the wrong image reference is visible ---
    B_IMAGE=$(kubectl get pod "$BROKEN_POD_NAME" -n "$NAMESPACE" \
        -o jsonpath='{.spec.containers[0].image}' 2>/dev/null)
    echo "       Broken image ref    : $B_IMAGE"

    if echo "$B_IMAGE" | grep -q "not-a-real-tag"; then
        pass "Broken pod uses the typo image 'not-a-real-tag'"
    else
        warn "Broken pod image is '$B_IMAGE' — expected a deliberately bogus tag"
    fi

    # --- kubectl get events shows the same failure as a timeline ---
    B_EVENTS=$(kubectl get events -n "$NAMESPACE" \
        --field-selector "involvedObject.name=$BROKEN_POD_NAME" \
        --sort-by='.lastTimestamp' 2>/dev/null)

    if echo "$B_EVENTS" | grep -qiE 'Failed|BackOff|ErrImagePull|ImagePullBackOff'; then
        pass "kubectl get events shows pull-failure events for the broken pod"
        echo "       Events (last 5):"
        echo "$B_EVENTS" | tail -5 | sed 's/^/         /'
    else
        fail "kubectl get events does not show pull-failure events for the broken pod"
    fi

    # --- sorted events must work ---
    if kubectl get events -n "$NAMESPACE" \
        --field-selector "involvedObject.name=$BROKEN_POD_NAME" \
        --sort-by='.lastTimestamp' >/dev/null 2>&1; then
        pass "kubectl get events --sort-by='.lastTimestamp' works"
    else
        fail "kubectl get events --sort-by='.lastTimestamp' failed"
    fi

    # --- teaching payload: describe vs events ---
    echo
    echo "  --- Difference between describe and get events (for your group post) ---"
    echo "  - kubectl describe <pod>  : one object, full spec/status, Events at the bottom,"
    echo "                              grouped per object, no global timeline."
    echo "  - kubectl get events      : cluster-wide Event stream across all objects,"
    echo "                              sortable by --sort-by='.lastTimestamp', ideal for"
    echo "                              'what happened recently?'."
    echo "  Both read the same underlying Event objects — different lenses."
    echo
    echo "       To delete the broken pod after taking screenshots:"
    echo "         kubectl delete pod $BROKEN_POD_NAME -n $NAMESPACE"

else
    warn "Skipping broken-pod checks — pod does not exist"
fi

# ------------------------------------------------------------
# Section 2 — crashloop baseline (optional bonus)
# ------------------------------------------------------------

section "2. CRASHLOOP BASELINE (BONUS)"

# Look for any pod in CrashLoopBackOff in the namespace
CRASH_POD=$(kubectl get pods -n "$NAMESPACE" \
    -o jsonpath='{range .items[?(@.status.containerStatuses[0].state.waiting.reason=="CrashLoopBackOff")]}{.metadata.name}{"\n"}{end}' 2>/dev/null \
    | head -1)

if [ -n "$CRASH_POD" ]; then
    pass "Found a CrashLoopBackOff pod for --previous testing: $CRASH_POD"

    if kubectl logs "$CRASH_POD" -n "$NAMESPACE" --previous --tail=5 >/dev/null 2>&1; then
        pass "kubectl logs --previous works on $CRASH_POD"
        echo "       Last log before crash:"
        kubectl logs "$CRASH_POD" -n "$NAMESPACE" --previous --tail=3 2>/dev/null \
            | sed 's/^/         /'
    else
        warn "kubectl logs --previous returned nothing for $CRASH_POD"
    fi
else
    warn "No CrashLoopBackOff pod present. Create a pod that crashes to test --previous logs."

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
    echo "🎉 WEEK 5 TROUBLESHOOTING VERIFICATION PASSED!"
    echo
    echo "The core exercise (deliberate image typo → describe + events)"
    echo "has been successfully verified."
    echo
    echo "  📸 Reminder: this task still requires a screenshot"
    echo "     of 'kubectl describe' and 'kubectl get events' for"
    echo "     the broken pod, plus an explanation of the difference,"
    echo "     shared on the group."
else
    echo "⚠️ WEEK 5 TROUBLESHOOTING VERIFICATION INCOMPLETE"
    echo
    echo "Fix the failed checks and run the script again."
fi

echo
echo "=========================================="

if [ "$FAIL" -gt 0 ]; then
    exit 1
else
    exit 0
fi
