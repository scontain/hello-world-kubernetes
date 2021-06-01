#!/bin/bash
set -ex

export SCONIFY_IMAGE="registry.scontain.com:5050/sconecuratedimages/community-edition-sconify-image:latest"
export CLI_IMAGE=$SCONIFY_IMAGE
export CROSSCOMPILER_IMAGE=$SCONIFY_IMAGE
export NATIVE_IMAGE="native-python"
# add RANDOM because minikube does not remove old images
export PYTHON_SCONIFIED_IMAGE="python-k8-test-$RANDOM"
export CAS_ADDR="5-3-0.scone-cas.cf"
export LAS_ADDR="localhost"

export GH_TOKEN=${GH_TOKEN:?"GH_TOKEN is not set! Please set to a valid github token."}
export SCONE_HUB_ACCESS_TOKEN=${SCONE_HUB_ACCESS_TOKEN:?"SCONE_HUB_ACCESS_TOKEN is not set! Please set to a valid registry.scontain.com token."}
export SCONE_HUB_USERNAME=${SCONE_HUB_USERNAME:?"SCONE_HUB_USERNAME is not set! Please set to a valid username for registry.scontain.com"}
export SCONE_HUB_EMAIL=v${SCONE_HUB_EMAIL:?"SCONE_HUB_EMAIL is not set! Please set to a valid username for registry.scontain.com"}

function check_host {
    [[ -z $(which docker) ]] && echo "Please install docker!" && exit 1
    [[ -z $(which kubectl) ]] && echo "Please install kubectl!" && exit 1
    [[ -z $(which helm) ]] && echo "Please install helm!" && exit 1
    [[ -z $(which minikube) ]] && echo "Please install minikube!" && exit 1
    
    echo ""
}

function prepare_host {
    if [[ ! -f ./host_is_ready ]]
    then
    echo "Preparing host"
    check_host

    minikube start --driver docker --cpus=2 --memory=2g
    if ! helm search repo sconeapps > /dev/null
    then
        helm repo add sconeapps https://${GH_TOKEN}@raw.githubusercontent.com/scontain/sconeapps/master/
        helm repo update
        if ! helm search repo sconeapps > /dev/null
        then
            echo "You need to configure access to Scontain helm repo https://github.com/scontain/sconeapps/" && exit 1
        fi
    fi

    if ! kubectl get secrets | grep sconeapps
    then
        kubectl create secret docker-registry sconeapps --docker-server=registry.scontain.com:5050 --docker-username=$SCONE_HUB_USERNAME --docker-password=$SCONE_HUB_ACCESS_TOKEN --docker-email=$SCONE_HUB_EMAIL 
    fi

    kubectl apply -f pvc/pv.yaml
    kubectl apply -f pvc/pvc.yaml

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
        --dlopen="2" \
        --volume="V1:/V1" \
        --dir=/code \
        --command="python3 /code/app.py" \
        --no-color \
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
    --set useSGXDevPlugin=scone \
    --set imagePullPolicy=IfNotPresent \
    --set scone.log=ERROR \
    --set scone.printVersion=true

    kubectl wait --for=condition=complete --timeout=30s job/python-service-$i-sconify-python-service
    kubectl logs job/python-service-$i-sconify-python-service
    done
    helm delete python-service-3 > /dev/null 2>&1 || true
    echo ""
    echo "Run this command to increace counter one more time:"
    echo "helm install python-service-3 charts/python-service \
    --set volumev1.persistence.enabled=true   \
    --set volumev1.persistence.existingClaim=test-pvc \
    --set useSGXDevPlugin=scone \
    --set imagePullPolicy=IfNotPresent \
    --set scone.log=ERROR \
    --set scone.printVersion=true;
    kubectl wait --for=condition=complete --timeout=30s job/python-service-3-sconify-python-service;
    kubectl logs job/python-service-3-sconify-python-service;
    "
}

function clean {
    minikube delete
    minikube image rm "$PYTHON_SCONIFIED_IMAGE"
    helm delete python-service
    helm delete my-las
    helm delete my-sgxdev
}

prepare_host

build_native_image

sconification

minikube image load "$PYTHON_SCONIFIED_IMAGE"
minikube ssh -- sudo rm -rf /tmp/V1/volume.fspf
minikube ssh -- sudo rm -rf /tmp/V1/num

sleep 10
deploy_to_kubernets
