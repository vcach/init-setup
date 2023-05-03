echo "Install EKS toolset"
echo "------------------------------------------------------"

echo "kubectl..."
sudo curl --silent --location -o /usr/local/bin/kubectl https://s3.us-west-2.amazonaws.com/amazon-eks/1.23.17/2023-03-17/bin/linux/amd64/kubectl
chmod +x /usr/local/bin/kubectl
kubectl completion bash >>  /home/ec2-user/.bash_completion
chown ec2-user.ec2-user /home/ec2-user/.bash_completion

echo "eksctl..."
curl -sLO "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz"
tar xz -C /tmp -f "eksctl_$(uname -s)_amd64.tar.gz"
sudo install -o root -g root -m 0755 /tmp/eksctl /usr/local/bin/eksctl
rm -f ./"eksctl_$(uname -s)_amd64.tar.gz"

echo "jq, getext, bash-completion, moreutils..."
sudo yum -y -q install jq gettext bash-completion moreutils
echo 'yq() {
  docker run --rm -i -v "${PWD}":/workdir mikefarah/yq "$@"
}' | tee -a ~/.bashrc && source ~/.bashrc


export AZS=($(aws ec2 describe-availability-zones --query 'AvailabilityZones[].ZoneName' --output text --region $AWS_REGION))


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

aws eks --region $AWS_REGION update-kubeconfig --name eks-copa-hackhaton2023

kubectl get nodes

STACK_NAME=$(eksctl get nodegroup --cluster eks-copa-hackhaton2023 -o json | jq -r '.[].StackName')
ROLE_NAME=$(aws cloudformation describe-stack-resources --stack-name $STACK_NAME | jq -r '.StackResources[] | select(.ResourceType=="AWS::IAM::Role") | .PhysicalResourceId')
echo "export ROLE_NAME=${ROLE_NAME}" | tee -a /home/ec2-user/.bash_profile

echo "Setup eks cluster"

echo "------------------------------------------------------"

rolearn=$(aws iam get-role --role-name TeamRole --query Role.Arn --output text)

eksctl create iamidentitymapping --cluster eks-copa-hackhaton2023 --arn ${rolearn} --group system:masters --username admin

echo "Added console credentials for console access"

echo "------------------------------------------------------"
echo "aws eks update-kubeconfig --name eks-copa-hackhaton2023 --region ${AWS_REGION}" | tee -a /home/ec2-user/.bash_profile
echo "export LAB_CLUSTER_ID=eks-copa-hackhaton2023" | tee -a /home/ec2-user/.bash_profile

echo "Completed cluster setup"

echo "------------------------------------------------------"
