# Text colors
BLACK="\e[30m"
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[34m"
MAGENTA="\e[35m"
CYAN="\e[36m"
WHITE="\e[37m"

# Bold and other effects
BOLD="\e[1m"
UNDERLINE="\e[4m"
RESET="\e[0m"

CLUSTER_NAME=mycluster


# With option clean, you clean the cluster including the namspaces
if [ -n "$1" ] && [ "$1" = "clean" ]; then
    echo -e "${BOLD}${RED}Cleaning k3d cluster and deleting namespaces.${RESET}"
    k3d cluster delete mycluster
    kubectl get ns --no-headers | awk '{print $1}' | grep -vE '^(default|kube-system|kube-public|kube-node-lease)$' | xargs sudo kubectl delete ns
    exit 0
fi

sudo apt-get update && sudo apt upgrade -y
sudo apt install net-tools -y curl
if ! docker --version >/dev/null 2>&1; then
    echo -e "${BOLD}${RED}docker is not installed. Installing now...${RESET}"
    sudo apt-get install docker.io -y
else
    echo -e "${GREEN}docker is already installed.${RESET}"
fi

if ! k3d --version >/dev/null 2>&1; then
    echo -e "${BOLD}${RED}k3d is not installed. Installing now...${RESET}"
    curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
else
    echo -e "${GREEN}k3d is already installed.${RESET}"
fi

if ! command -v kubectl >/dev/null 2>&1; then
    echo -e "${BOLD}${RED}kubectl is not installed. Installing now...${RESET}"
    sudo apt-get update && sudo apt upgrade -y
    sudo apt install curl apt-transport-https -y
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
else
    echo -e "${GREEN}kubectl already installed${RESET}"
fi


# Check if the cluster is already created or not
if ! k3d cluster list | grep -q "$CLUSTER_NAME"; then
    echo -e "${RED}Cluster not created, creating it now...${RESET}"
    k3d cluster create $CLUSTER_NAME
    echo -e "${GREEN}Cluster $CLUSTER_NAME created !${RESET}"
else
    echo -e "${GREEN}Cluster already created${RESET}"
fi

if [ "$(kubectl config current-context)" != "k3d-$CLUSTER_NAME" ]; then
    echo -e "${RED}Not using the expected context. Switching...${RESET}"
    kubectl config use-context "k3d-$CLUSTER_NAME"
else
    echo -e "${GREEN}Already using the correct context.${RESET}"
    kubectl config current-context #aucasou
fi


if [ "$(sudo kubectl get ns | grep -c argocd)" -ne 1 ]; then
    echo -e "${RED}No namespace named argocd. Creating it...${RESET}" 
    kubectl create namespace argocd
    kubectl create namespace dev
fi

kubectl apply -k /vagrant/

while [ "$(kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-server -o jsonpath="{.items[0].status.phase}")" != "Running" ]; do
  echo "Waiting for Argo CD server pod to be ready..."
  sleep 2
done

echo "Argo CD server is running! Starting port-forwarding..."
kubectl port-forward svc/argocd-server -n argocd 8080:443 --address 0.0.0.0 &
sleep 20
if ! argocd version >/dev/null 2>&1; then
    echo "argocd cli not installed... installing it"
    sudo curl -sSL -o /usr/local/bin/argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
    sudo chmod +x /usr/local/bin/argocd
    export SECRET_PASS=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
    export | grep SECRET_PASS
    curl http://localhost:8080
    argocd login https://localhost:8080 --username admin --password $SECRET_PASS --insecure
    argocd repo add https://github.com/Ezuker/iot-argocd.git
    argocd app create my-app \
        --repo https://github.com/Ezuker/iot-argocd.git \
        --path k8s-manifests \
        --dest-server https://kubernetes.default.svc \
        --dest-namespace dev
    argocd app sync my-app
fi
