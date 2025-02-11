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
    sudo k3d cluster delete mycluster
    sudo kubectl get ns --no-headers | awk '{print $1}' | grep -vE '^(default|kube-system|kube-public|kube-node-lease)$' | xargs sudo kubectl delete ns
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
    sudo curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | sudo bash
else
    echo -e "${GREEN}k3d is already installed.${RESET}"
fi

if ! command -v kubectl >/dev/null 2>&1; then
    echo -e "${BOLD}${RED}kubectl is not installed. Installing now...${RESET}"
    sudo apt-get update && sudo apt upgrade -y
    sudo apt install curl apt-transport-https -y
    sudo curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
else
    echo -e "${GREEN}kubectl already installed${RESET}"
fi


# Check if the cluster is already created or not
if ! k3d cluster list | grep -q "$CLUSTER_NAME"; then
    echo -e "${RED}Cluster not created, creating it now...${RESET}"
    sudo k3d cluster create $CLUSTER_NAME
    echo -e "${GREEN}Cluster $CLUSTER_NAME created !${RESET}"
else
    echo -e "${GREEN}Cluster already created${RESET}"
fi

if [ "$(sudo kubectl config current-context)" != "k3d-$CLUSTER_NAME" ]; then
    echo -e "${RED}Not using the expected context. Switching...${RESET}"
    sudo kubectl config use-context "k3d-$CLUSTER_NAME"
else
    echo -e "${GREEN}Already using the correct context.${RESET}"
fi


if [ "$(sudo kubectl get ns | grep -c argocd)" -ne 1 ]; then
    echo -e "${RED}No namespace named argocd. Creating it...${RESET}" 
    sudo kubectl create namespace argocd
    sudo kubectl create namespace dev
fi
sudo kubectl apply -k .
sleep 10
sudo kubectl port-forward svc/argocd-server -n argocd 8080:443 &

if ! brew --version; then
    git clone https://github.com/Homebrew/brew ~/homebrew
fi
if ! argocd version; then
    brew install argocd
fi
argocd app create <APP_NAME> \
  --repo <REPO_URL> \
  --path <PATH_TO_MANIFESTS> \
  --dest-server <K8S_API_SERVER> \
  --dest-namespace <NAMESPACE>
