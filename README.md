# Requirements

- Minikube
- Docker
- Helm 3
- kubectl
- Access to https://github.com/scontain/sconeapps/
- Access to https://gitlab.scontain.com/

# Demo

This a demonstration of one step transformation of Python native image (`./native-image/Dockerfile`) to SCONE-enabled image and subsequent execution on K8s cluster (imitated with minikube).
Transformation of the native image and generation of helm chart (`./charts`) for it is done with sconify-image tool (`registry.scontain.com:5050/sconecuratedimages/community-edition-sconify-image:latest`)

# To run
Set token generated here https://github.com/settings/tokens/new  to this variable `GH_TOKEN` 
Set token generated here https://gitlab.scontain.com/-/profile/personal_access_tokens to this variable `SCONE_HUB_ACCESS_TOKEN` 
Set `SCONE_HUB_USERNAME` and `SCONE_HUB_EMAIL`

To run demo:
```bash
export GH_TOKEN=<your token>
export SCONE_HUB_ACCESS_TOKEN=<your token>
export SCONE_HUB_USERNAME=<your username>
export SCONE_HUB_EMAIL=<your email>
./demo.sh
```



