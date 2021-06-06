#!/bin/bash
set -e

source ./minikube.sh

export SCONIFY_IMAGE="registry.scontain.com:5050/sconecuratedimages/community-edition-sconify-image:latest"
export CLI_IMAGE=$SCONIFY_IMAGE
export CROSSCOMPILER_IMAGE=$SCONIFY_IMAGE
export NATIVE_IMAGE="native-python"
# add RANDOM because minikube does not remove old images
export PYTHON_SCONIFIED_IMAGE="python-k8-test-$RANDOM"
export CAS_ADDR="5-3-0.scone-cas.cf"
export LAS_ADDR="localhost"

export SWITCH_MINIKUBE="no"
export SWITCH_AKS="no"
export SWITCH_CLEAN="no"
export SWITCH_DEBUG="no"
export SWITCH_VERBOSE="no"

export REGISTRY=""
export DOCKER_CONFIG=""
export SGX_DEVICE="scone"
export SET_PULL_SECRET=""
export PULL_SECRET_NAME="sconeapps" # secret for sconeapps
export PULL_SECRET_NAME2=${K8S_IMAGE_PULL_SECRET:-"regcred"}  # secret for built image
export PULL_POLICY="IfNotPresent"
export PUSH=""


function issue_error_exit_message {
    errcode=$?
    trap no_error_message EXIT
    if [[ $errcode != 0 ]] ; then
        echo "ERROR: demo failed at lines:"
        printf '%s,'  "${BASH_LINENO[@]}"
    else
        echo "OK"
    fi
    exit $errcode
}

trap issue_error_exit_message EXIT


function clean {
    helm uninstall python-service-0 || true
    helm uninstall python-service-1 || true
    helm uninstall python-service-2 || true
    helm uninstall python-service-3 || true
    helm uninstall my-las || true
    helm uninstall my-sgxdev || true
    rm -f host_is_ready
    rm -f pvc_minikube.yaml

    minikube_delete
    echo "Done cleaning!"
    exit 0
}

function print_message {
    local MESSAGE=$1
    echo -e "${MESSAGE}" 1>&2
}

function usage() {
    print_message "Usage $(basename ${BASH_SOURCE[0]}) [-h ] [-x] [-v] [-a] [-r] [-m] [-c]

        \nSwitches:
        -h\tPrint this message and exit
        -x\tEnable debug mode
        -v\tEnable verbose mode (print Dockerfile and session of sconified image)
        -m\tRun with minikube
        -a\tRun on AKS
        -n\tRun on single node Kubernetes cluster
        -r\tRegistry to push image (on AKS and single node Kubernetes)
        -c\tClean
        "
}

while getopts ":hxvamncr:" opt; do
    case ${opt} in
        \?)
            usage
            exit 1
            ;;
        h)
            usage
            exit 1
            ;;
        x)
            set -x
            export SWITCH_DEBUG="yes"
            ;;
        v)
            export SWITCH_VERBOSE="yes"
            ;;
        a)
            export SWITCH_AKS="yes"
            ;;
        m)
            export SWITCH_MINIKUBE="yes"
            ;;
        n)
            export SWITCH_K8s="yes"
            ;;
        c)
            export SWITCH_CLEAN="yes"
            ;;
        r)
            REGISTRY="${OPTARG}"
            ;;
 esac
done

export GH_TOKEN=${GH_TOKEN:?"GH_TOKEN is not set! Please set to a valid github token."}
export SCONE_HUB_ACCESS_TOKEN=${SCONE_HUB_ACCESS_TOKEN:?"SCONE_HUB_ACCESS_TOKEN is not set! Please set to a valid registry.scontain.com token."}
export SCONE_HUB_USERNAME=${SCONE_HUB_USERNAME:?"SCONE_HUB_USERNAME is not set! Please set to a valid username for registry.scontain.com"}
export SCONE_HUB_EMAIL=${SCONE_HUB_EMAIL:?"SCONE_HUB_EMAIL is not set! Please set to a valid username for registry.scontain.com"}

[[ $SWITCH_CLEAN == "yes" ]] && echo "Cleaning .." && clean
[[ $SWITCH_AKS == "no" ]] && [[ $SWITCH_MINIKUBE == "no" ]]  && [[ $SWITCH_K8s == "no" ]] && echo "Please specify either -m (for minikube demo) or -a (for AKS demo) or -n (for Kubernetes)!" && exit 1

[[ $SWITCH_VERBOSE == "yes" ]] && export VERBOSE="--verbose"
[[ $SWITCH_DEBUG == "yes" ]] && export DEBUG="--debug"

if [[ $SWITCH_AKS == "yes" || $SWITCH_K8s == "yes" ]]
then
    [[ $SWITCH_MINIKUBE == "yes" ]] && echo "Please specify either -m or -a or -n" && exit 1
    [[ $SWITCH_AKS == "yes" && $SWITCH_K8s == "yes" ]] && echo "Please specify either -n or -a, not both!" && exit 1
    [[ -z $REGISTRY ]] && echo "Please specify registry name to push images to (-r option)!" && exit 1  
    export DOCKER_CONFIG="-v $HOME/.docker/config.json:/root/.docker/config.json"
    export PYTHON_SCONIFIED_IMAGE=$REGISTRY":"$PYTHON_SCONIFIED_IMAGE
    [[ $SWITCH_AKS = "yes" ]] && export SGX_DEVICE="azure"
    export SET_PULL_SECRET="--set imagePullSecrets[0].name=$PULL_SECRET_NAME2"
    export PULL_POLICY="Always"
    export PUSH="--push-image"
fi


function check_host {
    [[ -z $(which docker) ]] && echo "Please install docker!" && exit 1
    [[ -z $(which kubectl) ]] && echo "Please install kubectl!" && exit 1
    [[ -z $(which helm) ]] && echo "Please install helm!" && exit 1
    [[ $SWITCH_MINIKUBE = "yes" ]] && [[ -z $(which minikube) ]] && echo "Please install minikube!" && exit 1
    echo ""
}

function prepare_host {
    if [[ ! -f ./host_is_ready ]]
    then
    echo "Preparing host"
    check_host

    [[ $SWITCH_MINIKUBE = "yes" ]] && minikube_start "2" "2g"

    if ! helm search repo sconeapps > /dev/null
    then
        helm repo add sconeapps https://${GH_TOKEN}@raw.githubusercontent.com/scontain/sconeapps/master/
        helm repo update
        if ! helm search repo sconeapps > /dev/null
        then
            echo "You need to configure access to Scontain helm repo https://github.com/scontain/sconeapps/" && exit 1
        fi
    fi

    if ! kubectl get secrets | grep $PULL_SECRET_NAME
    then
        kubectl create secret docker-registry $PULL_SECRET_NAME --docker-server=registry.scontain.com:5050 --docker-username=$SCONE_HUB_USERNAME --docker-password=$SCONE_HUB_ACCESS_TOKEN --docker-email=$SCONE_HUB_EMAIL 
    fi

    helm repo update
    helm install my-sgxdevplugin sconeapps/sgxdevplugin
    helm install my-las sconeapps/las

    docker pull ${SCONIFY_IMAGE} || (echo "You need access to registry.scontain.com:5050" && exit 1)

    touch host_is_ready
    else
    echo "Host is ready to run demo! Skip"
    fi
}

function build_native_image {
    echo "Building native image"
    docker build -t $NATIVE_IMAGE $PWD/native-image
}

function sconification {
    echo "Sconifying $NATIVE_IMAGE into $PYTHON_SCONIFIED_IMAGE"

docker run -it --rm \
    -v $PWD/charts:/charts \
    -v /var/run/docker.sock:/var/run/docker.sock \
    ${DOCKER_CONFIG} \
    ${SCONIFY_IMAGE} \
    sconify_image \
        --from="$NATIVE_IMAGE" \
        --to="$PYTHON_SCONIFIED_IMAGE" \
        --create-namespace \
        --namespace="ns-$RANDOM$RANDOM$RANDOM" \
        --name="python-session" \
        --service-name="python-service" \
        --cli="$CLI_IMAGE" \
        --crosscompiler="$CROSSCOMPILER_IMAGE" \
        --cas-debug \
        --cas="$CAS_ADDR" \
        --las="$LAS_ADDR" \
        --heap="256m" \
        --stack="4m" \
        --binary="/usr/bin/python3.7" \
        --dlopen="1" \
        --volume="V1:/V1" \
        --dir=/code \
        --dir=/usr/lib \
        --command="python3 /code/app.py" \
        --no-color \
        $VERBOSE \
        $DEBUG \
        $PUSH \
        --k8s-helm-workload-type=job \
        --k8s-helm-output-dir=/charts
}

function deploy_to_kubernets {
    for i in $(seq 0 2)
    do
    helm delete python-service-$i > /dev/null 2>&1 || true
    helm install python-service-$i charts/python-service \
    --set volumev1.persistence.enabled=true   \
    --set volumev1.persistence.existingClaim=test-pvc \
    --set useSGXDevPlugin=$SGX_DEVICE \
    $SET_PULL_SECRET \
    --set imagePullPolicy=$PULL_POLICY \
    --set scone.log=ERROR \
    --set scone.printVersion=true

    kubectl wait --for=condition=complete --timeout=60s job/python-service-$i-sconify-python-service
    kubectl logs job/python-service-$i-sconify-python-service
    helm uninstall python-service-$i > /dev/null 2>&1 || true
    done
    echo ""
    echo "Run this command to increase counter one more time:"
    echo "helm install python-service-3 charts/python-service \
    --set volumev1.persistence.enabled=true   \
    --set volumev1.persistence.existingClaim=test-pvc \
    $SET_PULL_SECRET \
    --set useSGXDevPlugin=$SGX_DEVICE \
    --set imagePullPolicy=$PULL_POLICY \
    --set scone.log=ERROR \
    --set scone.printVersion=true;
    kubectl wait --for=condition=complete --timeout=45s job/python-service-3-sconify-python-service;
    kubectl logs job/python-service-3-sconify-python-service;
    "
}

function aks_recreate_pvc() {
    kubectl delete pvc --all
    kubectl apply -f pvc/pvc_azure.yaml
}


function k8s_recreate_pvc() {
    echo "If the following deletes block, it means that the volume (claim) is still used."
    kubectl delete pvc test-pvc || true
    kubectl delete pv test-pvc   || true
    kubectl create -f pv/pv_node.yaml || echo "PV already exists?"
    kubectl create -f pvc/pvc_node.yaml || echo "PVC already exists?"
}
prepare_host

build_native_image

sconification

echo "..."

[[ $SWITCH_MINIKUBE = "yes" ]] &&  minikube_image_load "$PYTHON_SCONIFIED_IMAGE" && minikube_recreate_pvc
[[ $SWITCH_AKS = "yes" ]] && aks_recreate_pvc
[[ $SWITCH_K8s = "yes" ]] && k8s_recreate_pvc

sleep 10
deploy_to_kubernets
