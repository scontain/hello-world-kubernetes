
function minikube_start() {
    local cpu="$1"
    local mem="$2"
    [[ -z $cpu ]] && echo "No CPU specified for minikube! Using 2 as a default." && cpu="2"
    [[ -z $mem ]] && echo "No memory specified for minikube! Using 2g as a default." && mem="2g"

    minikube start --driver docker --cpus=$cpu --memory=$mem
}

function minikube_image_load() {
    local image="$1"
    [[ -z $image ]] && "image that must be uploaded to minikube is not set! Something went wrong! Use set -x for troubleshooting."

    minikube image load $image
}

function minikube_recreate_pvc() {
    # imporve this maybe like:
    # kubectl get pods --all-namespaces -o=json | jq -c '.items[] | {name: .metadata.name, namespace: .metadata.namespace, claimName: .spec |  select( has ("volumes") ).volumes[] | select( has ("persistentVolumeClaim") ).persistentVolumeClaim.claimName }'
    # but need to ensure that jq is installed
    # or kubectl describe pvc | grep -A 5 "Used By"
    # delete services that suposedly is using our pvc
    echo "Removing python services that might be using test-pvc"
    set -x
    helm delete python-service-0 || true
    helm delete python-service-1 || true
    helm delete python-service-2 || true
    helm delete python-service-3 || true
    set +x

    kubectl delete pvc --all
    cat > pvc_minikube.yaml << EOF
kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: test-pvc
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
EOF

    kubectl apply -f pvc_minikube.yaml
}

function minikube_delete() {
    [[ -n $(which minikube) ]] && minikube delete || true
}