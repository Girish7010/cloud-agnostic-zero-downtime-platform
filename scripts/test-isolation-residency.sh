#!/usr/bin/env bash
# Evidence test: tenant isolation and EU residency guards (local kind).
set -uo pipefail
echo "== isolation/residency test started $(date '+%F %T %Z')"
pass=0; fail=0; ok(){ echo "PASS: $*"; pass=$((pass+1)); }; bad(){ echo "FAIL: $*"; fail=$((fail+1)); }

echo; echo "--- 1. Policy gate: EU tenant declaring a US region must be rejected"
mkdir -p gitops/tenants/zz-test-eu-in-us
sed -e 's/acme-eu/zz-test-eu-in-us/g' -e 's/region: eu-west-1/region: us-east-1/' gitops/tenants/acme-eu/values.yaml > gitops/tenants/zz-test-eu-in-us/values.yaml
if scripts/onboard-tenant.sh zz-test-eu-in-us; then bad "EU tenant in us-east-1 was accepted"; else ok "onboarding refused EU tenant in us-east-1"; fi
rm -rf gitops/tenants/zz-test-eu-in-us
kubectl get ns tenant-zz-test-eu-in-us >/dev/null 2>&1 && bad "namespace was created" || ok "no namespace/resources created for rejected tenant"

echo; echo "--- 2. Scheduler guard: pod restricted to EU regions on a node without an EU region label"
kubectl get nodes -L topology.kubernetes.io/region
helm template tenant-acme-eu deploy/chart -n tenant-acme-eu -f deploy/environments/local.yaml -f gitops/tenants/acme-eu/values.yaml \
  --set tenant.enforceRegion=true --set 'tenant.allowedRegions={eu-west-1,eu-central-1}' --show-only templates/api.yaml \
  | python3 -c '
import sys,yaml
d=[x for x in yaml.safe_load_all(sys.stdin) if x and x["kind"]=="Deployment"][0]
pod={"apiVersion":"v1","kind":"Pod","metadata":{"name":"residency-probe","namespace":"tenant-acme-eu","labels":{"test":"residency"}},"spec":d["spec"]["template"]["spec"]}
print(yaml.safe_dump(pod))' | kubectl apply -f -
for _ in $(seq 1 15); do
  msg=$(kubectl get events -n tenant-acme-eu --field-selector involvedObject.name=residency-probe,reason=FailedScheduling -o jsonpath='{.items[-1:].message}' 2>/dev/null)
  [ -n "$msg" ] && break; sleep 2; done
phase=$(kubectl get pod residency-probe -n tenant-acme-eu -o jsonpath='{.status.phase}')
echo "pod phase=$phase event: $msg"
[ "$phase" = Pending ] && [[ "$msg" == *"affinity"* ]] && ok "scheduler refused to place EU-pinned pod on non-EU node" || bad "EU-pinned pod was scheduled"
kubectl delete pod residency-probe -n tenant-acme-eu --wait=false

echo; echo "--- 3. Network isolation (NetworkPolicy enforced by kindnet)"
probe() { # $1=namespace of client  $2=host:port  [$3=pod labels] -> prints connected|blocked
  kubectl run "np-probe-$RANDOM" -n "$1" --rm -i --restart=Never --quiet --image=redis:7-alpine --labels="${3:-role=np-probe}" \
    --overrides='{"spec":{"securityContext":{"runAsNonRoot":true,"runAsUser":1000,"seccompProfile":{"type":"RuntimeDefault"}},"containers":[{"name":"p","image":"redis:7-alpine","command":["sh","-c","timeout 5 nc -z -w 4 '"${2%:*} ${2#*:}"' && echo connected || echo blocked"],"securityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]}}}]}}' 2>/dev/null | tail -1
}
# Positive controls prove the probe itself can connect (otherwise "blocked" means nothing).
r=$(probe tenant-acme-eu tenant-acme-eu-api:8080); echo "acme (unlabelled pod) -> own api: $r"; [ "$r" = connected ] && ok "control: same-namespace client reaches tenant API" || bad "control failed: own API unreachable ($r)"
r=$(probe tenant-acme-eu tenant-acme-eu-redis:6379 app.kubernetes.io/part-of=tenant-acme-eu); echo "acme (release pod) -> own redis: $r"; [ "$r" = connected ] && ok "control: release pod reaches its own Redis" || bad "control failed: own Redis unreachable ($r)"
r=$(probe tenant-acme-eu tenant-acme-eu-redis:6379); echo "acme (non-release pod) -> own redis: $r"; [ "$r" = blocked ] && ok "non-release pod in same namespace blocked from Redis" || bad "Redis open to any pod ($r)"
r=$(probe tenant-acme-eu devops-platform-redis.devops-platform:6379 app.kubernetes.io/part-of=devops-platform); echo "acme (pod spoofing shared release label) -> shared redis: $r"; [ "$r" = blocked ] && ok "tenant blocked from shared stack Redis" || bad "cross-tenant Redis reachable ($r)"
r=$(probe tenant-acme-eu tenant-globex-eu-api.tenant-globex-eu:8080); echo "acme -> globex api: $r"; [ "$r" = blocked ] && ok "tenant blocked from another tenant's API" || bad "cross-tenant API reachable ($r)"
r=$(probe tenant-acme-eu tenant-globex-eu-redis.tenant-globex-eu:6379); echo "acme -> globex redis: $r"; [ "$r" = blocked ] && ok "tenant blocked from another tenant's Redis" || bad "cross-tenant Redis reachable ($r)"

echo; echo "--- 4. Per-tenant labels (visibility) on running pods"
kubectl get pods -A -l platform.io/tenant -L platform.io/tenant,platform.io/deployment-mode,platform.io/data-residency --no-headers | awk '{print $1, $2, $(NF-2), $(NF-1), $NF}'
echo; echo "== RESULT: $pass passed, $fail failed  ($(date '+%F %T %Z'))"
[ "$fail" -eq 0 ]
