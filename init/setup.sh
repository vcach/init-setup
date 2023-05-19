echo "Install EKS toolset"
echo "------------------------------------------------------"

#curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
#unzip awscliv2.zip
#sudo ./aws/install
#aws --version
#. ~/.bash_profile

echo "kubectl..."
sudo curl --silent --location -o /usr/local/bin/kubectl https://s3.us-west-2.amazonaws.com/amazon-eks/1.23.17/2023-03-17/bin/linux/amd64/kubectl
sudo chmod +x /usr/local/bin/kubectl
kubectl completion bash >>  /home/ec2-user/.bash_completion
sudo chown ec2-user.ec2-user /home/ec2-user/.bash_completion

echo "eksctl..."
sudo curl -sLO "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz"
sudo tar xz -C /tmp -f "eksctl_$(uname -s)_amd64.tar.gz"
sudo install -o root -g root -m 0755 /tmp/eksctl /usr/local/bin/eksctl
rm -f ./"eksctl_$(uname -s)_amd64.tar.gz"

echo "jq, getext, bash-completion, moreutils..."
sudo yum -y -q install jq gettext bash-completion moreutils
echo 'yq() {
  docker run --rm -i -v "${PWD}":/workdir mikefarah/yq "$@"
}' | tee -a ~/.bashrc && source ~/.bashrc

echo "helm..."
curl -sSL https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | bash
helm repo add eks https://aws.github.io/eks-charts
helm repo update

echo "export ACCOUNT_ID=$(aws sts get-caller-identity --output text --query Account)"  >>  ~/.bash_profile
echo "export AWS_REGION=$(curl -s 169.254.169.254/latest/dynamic/instance-identity/document | jq -r '.region')"  >>  ~/.bash_profile
.  ~/.bash_profile
echo "export AZS=($(aws ec2 describe-availability-zones --query 'AvailabilityZones[].ZoneName' --output text --region $AWS_REGION))"  >>  ~/.bash_profile
.  ~/.bash_profile
source ~/.bash_profile

aws configure set default.region ${AWS_REGION}
aws configure get default.region

#export AZS=($(aws ec2 describe-availability-zones --query 'AvailabilityZones[].ZoneName' --output text --region $AWS_REGION))
echo "creating eks cluster in region ${AWS_REGION} in AZs ${AZS[0]} ${AZS[1]} ${AZS[2]}"


cat << EOF > ekscluster.yaml
---
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig

metadata:
  name: eks-copa-hackhaton2023
  region: ${AWS_REGION}
  version: "1.23"

availabilityZones: ["${AZS[0]}", "${AZS[1]}", "${AZS[2]}"]

managedNodeGroups:
- name: nodegroup
  desiredCapacity: 3
  instanceType: t3.medium
  ssh:
    enableSsm: true

# To enable all of the control plane logs, uncomment below:
# cloudWatch:
#  clusterLogging:
#    enableTypes: ["*"]

EOF

eksctl create cluster -f ekscluster.yaml

echo "AWS Load Balancer Controller..."

eksctl utils associate-iam-oidc-provider \
    --region ${AWS_REGION} \
    --cluster eks-copa-hackhaton2023 \
    --approve

curl -O https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.4.7/docs/install/iam_policy.json
aws iam create-policy \
    --policy-name AWSLoadBalancerControllerIAMPolicy \
    --policy-document file://iam_policy.json
    
rm iam_policy.json

eksctl create iamserviceaccount \
  --cluster eks-copa-hackhaton2023 \
  --namespace kube-system \
  --name aws-load-balancer-controller \
  --attach-policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/AWSLoadBalancerControllerIAMPolicy \
  --override-existing-serviceaccounts \
  --approve

helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=eks-copa-hackhaton2023 \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller 

#aws eks --region $AWS_REGION update-kubeconfig --name eks-copa-hackhaton2023

#kubectl get nodes

#STACK_NAME=$(eksctl get nodegroup --cluster eks-copa-hackhaton2023 -o json | jq -r '.[].StackName')
#ROLE_NAME=$(aws cloudformation describe-stack-resources --stack-name $STACK_NAME | jq -r '.StackResources[] | select(.ResourceType=="AWS::IAM::Role") | .PhysicalResourceId')
#echo "export ROLE_NAME=${ROLE_NAME}" | tee -a /home/ec2-user/.bash_profile

#echo "Setup eks cluster"

#echo "------------------------------------------------------"

#rolearn=$(aws iam get-role --role-name TeamRole --query Role.Arn --output text)

#eksctl create iamidentitymapping --cluster eks-copa-hackhaton2023 --arn ${rolearn} --group system:masters --username admin

#echo "Added console credentials for console access"

#echo "------------------------------------------------------"

echo "Completed cluster setup"

echo "------------------------------------------------------"
