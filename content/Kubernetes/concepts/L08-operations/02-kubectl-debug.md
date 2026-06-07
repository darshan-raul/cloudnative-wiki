# kubectl Debug Toolkit

*"https://kubernetes.io/docs/tasks/debug/"*

A reference for the **`kubectl` commands** you reach for when something is wrong. Bookmark this — you'll come back to it often.

## Pod-level

```bash
# what's going on with this Pod?
kubectl describe pod <name>
# top of output: status, conditions (Pending, ContainerStatus, Ready, ...)
# bottom of output: Events — this is the most useful part

# live logs (one container)
kubectl logs -f <pod>

# multi-container Pod — pick one
kubectl logs <pod> -c <container>

# all containers in the Pod, with timestamps, previous-instance if restarted
kubectl logs <pod> --all-containers=true --timestamps --previous

# stream logs from all Pods matching a label
kubectl logs -f -l app=foo

# run a one-off command in a running container
kubectl exec -it <pod> -- bash

# exec into a specific container
kubectl exec -it <pod> -c <container> -- sh
```

## Debugging a stuck Pod without exec

When `kubectl exec` doesn't work (image has no shell, container is broken):

```bash
# run a debug container in the same Pod
kubectl debug -it <pod> --image=busybox --target=<container>

# ephemeral debug container (k8s 1.23+, needs ephemeralContainers enabled)
kubectl debug -it <pod> --image=ubuntu --target=<container> -- bash

# copy the broken Pod's filesystem to a debug Pod
kubectl debug <pod> --image=ubuntu --copy-to=<new-pod> --share-processes -- bash

# run a debug Pod on a specific node, with the host filesystem mounted
kubectl debug node/<node> -it --image=ubuntu
# Pod is named <node>-debug, mount /host to see the node's root filesystem
```

`kubectl debug` creates **ephemeral containers** — debug-only sidecars that aren't part of the Pod spec. They live as long as the session does, then disappear.

## Networking

```bash
# is the Pod reachable? (run from inside the Pod)
kubectl exec <pod> -- curl -v http://<service>.<ns>:8080

# is DNS resolving? (from inside the Pod)
kubectl exec <pod> -- nslookup <service>.<ns>.svc.cluster.local

# resolve the service IP from the Pod
kubectl exec <pod> -- getent hosts <service>.<ns>

# trace the route
kubectl exec <pod> -- traceroute <target>

# what's listening on what port?
kubectl exec <pod> -- ss -tlnp
```

## Resources and metrics

```bash
# node resource usage
kubectl top nodes

# Pod resource usage (needs metrics-server)
kubectl top pods
kubectl top pods -A --sort-by=memory

# container-level breakdown
kubectl top pods <pod> --containers

# node capacity and allocatable
kubectl describe node <node> | grep -A5 "Allocated resources"
```

## Events and conditions

```bash
# events sorted by time
kubectl get events --sort-by=.lastTimestamp -A
kubectl get events -n <ns> --field-selector involvedObject.name=<pod>
kubectl get events -A --field-selector type=Warning

# Pod conditions (Scheduled, Ready, Initialized, ContainersReady)
kubectl get pod <pod> -o jsonpath='{.status.conditions[*].type}: {.status.conditions[*].status}'
```

## API debugging

```bash
# raw API request as a specific ServiceAccount
kubectl auth can-i create pods --as=system:serviceaccount:<ns>:<sa>
kubectl auth can-i list secrets --all-namespaces

# what can a user do?
kubectl auth can-i --list --as=user@example.com

# raw API call (bypasses kubectl auth checks)
kubectl get --raw='/api/v1/namespaces/<ns>/pods/<pod>/log?follow=true'

# dump full Pod spec
kubectl get pod <pod> -o yaml
kubectl get pod <pod> -o jsonpath='{.spec}' | jq .

# show all resources, even those from CRDs
kubectl api-resources
```

## Node-level

```bash
# SSH into the node (if you have access)
ssh <node>

# then on the node:
crictl ps                 # list containers
crictl logs <id>          # container logs without kubectl
crictl inspect <id>       # container details
journalctl -u kubelet     # kubelet logs
journalctl -u containerd  # container runtime logs

# what does the node look like to the kubelet?
kubectl describe node <node>
# Capacity, Allocatable, Conditions, Addresses, ...
```

## Common one-liners

```bash
# all Pods not Running
kubectl get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded

# all Pods that restarted at least once
kubectl get pods -A -o json | jq -r '.items[] | select(.status.containerStatuses[]?.restartCount > 0) | "\(.metadata.namespace)/\(.metadata.name): \(.status.containerStatuses[].restartCount)"'

# all image pull errors
kubectl get events -A --field-selector reason=Failed

# nodes that aren't Ready
kubectl get nodes -o json | jq -r '.items[] | select(.status.conditions[] | select(.type=="Ready" and .status!="True")) | .metadata.name'

# what's using the most memory?
kubectl top pods -A --sort-by=memory | head

# what's using the most CPU?
kubectl top pods -A --sort-by=cpu | head

# storage left on a node
ssh <node> 'df -h /var/lib/containerd'

# find which Pod is on which node
kubectl get pods -A -o wide --sort-by=.spec.nodeName
```

## Gotchas

* **`kubectl logs` doesn't follow across restarts by default.** Add `--previous` to see the logs of the previous container instance. Useful when a container is crashlooping.
* **Multi-container Pods need `-c` to pick a container.** Without it, you get an error like "log is ambiguous".
* **`kubectl exec` requires the container to have the binary you're running** (bash, sh, etc.). Alpine-based images often don't have bash. Try `sh`.
* **Ephemeral debug containers require `--feature-gates=EphemeralContainers=true`** on older clusters. k8s 1.23+ has it on by default.
* **metrics-server must be installed** for `kubectl top` to work. Managed clusters usually have it; kubeadm clusters often don't.
* **`kubectl describe` truncates the events list.** For the full list, use `kubectl get events`.
* **`kubectl get pod` shows the Pod, not its containers.** If a container is failing but the Pod is "Running", you're not seeing the right level of detail. Use `-o yaml` or `describe`.
* **`kubectl auth can-i` is what the API server thinks you can do.** It's not a security boundary; it's a way to debug RBAC.

## When all else fails

```bash
# delete and let the controller recreate it (last resort)
kubectl delete pod <pod>

# the Pod was probably already broken; recreation usually fails the same way
# but it clears the "Completed" / "Terminating" state and gives you fresh events

# if it's a Deployment issue, rollback
kubectl rollout undo deployment/<name>

# check etcd is healthy (you need access to the control plane)
ETCDCTL_API=3 etcdctl endpoint health \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key
```
