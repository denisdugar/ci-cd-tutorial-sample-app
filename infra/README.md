# CICD AWS EKS infrastructure

## Pre-requirements
Terraform v1.10.3
 
aws-cli v2.23.13

eksctl v0.203.0

kubectl v1.32.1

User in AWS with policies for creating all needed resources.
##
In AWS console please create a secret in Secrets Manager with the username and password you will be using for jenkins:
```sh
{"username":"<your_username>","password":"<your_password>"}
```
Also, create a parameter in AWS Parameter Store with the script that creates a user in Jenkins:
```sh
#!groovy

import jenkins.model.*
import hudson.security.*

def instance = Jenkins.getInstance()

def hudsonRealm = new HudsonPrivateSecurityRealm(false)
hudsonRealm.createAccount('<your_username>','<your_password>')
instance.setSecurityRealm(hudsonRealm)

def strategy = new FullControlOnceLoggedInAuthorizationStrategy()
strategy.setAllowAnonymousRead(false)
instance.setAuthorizationStrategy(strategy)
instance.save()
```
Add secret name and parameter name to terraform.tfvars file

## Creating infrastructure

In infra directory, run terraform commands to create network infrastructure for Jenkins and EKS cluster and create Jenkins instance
```sh
terraform init
terraform apply --auto-approve
```

After all resources are created, wait for 5-10 minutes for user-data script is finished. Open AWS console and go to Load Balancers. Take newly created Load Balancer URL. This is URL for your Jenkins. Your credentials are the same you paste in the script before.

Login to your account and go to Managed Jenkins -> Credentials -> Global and create DockerHub credentials to your DockerHub account. 

After that you can go to + New Item and create 2 pipelines
1. PyTest - testing python code (Jenkinsfile_pytest)
2. DockerBuild - build and push docker image to your DockerHub (Jenkinsfile_build_docker)
   For changing default DockerHub repo please change it in Jenkinsfile_build_docker file

PyTest pipeline should work everytime some updates are pushed to GitHub repo. Add this trigger in pipeline and create webhook in the settings of the GitHub repo
the link should look like:
```sh
http://<jenkins_server>/github-webhook/
```
Disable ssl and choose Just the push event

After all this setup, you can go to your cmd infra directory. Take outputs from terraform command with vpc and subnet ids and put them to cluster.yaml file. 
Now you can run
```sh
eksctl create cluster -f cluster.yaml
```
It will take 10-30 min and create EKS cluster in AWS.

After EKS cluster is created use 
```sh
docker login
```
to login to your docker account. It will create /home/user/.docker/config.json with your docker credentials.
We will use it to create kubernetes secret for pulling image from your private docker repo

Apply kustomization file to create deployment and service. (Choose image for your repo)
```sh
kubectl apply -k .
```

Now we can add ArgoCD to EKS cluster run those commands and create LoadBalancer to reach ArgoCd UI
```sh
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "LoadBalancer"}}'
```

Install ArgoCD cli
```sh
curl -sSL -o argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
chmod +x argocd
sudo mv argocd /usr/local/bin/
```

Use this command to get admin password for login ArgoCD
```sh
argocd admin initial-password -n argocd
```

Use kubectl to get LoadBalancer url for ArgoCD
```sh
kubectl get service -n argocd
```

For create application in ArgoCD use this command (change image)
```sh
kubectl apply -f application.yaml
```

Let's add ArgoCD image updater to our cluster for automaticaly update repo and deploy if new version apears in DockerHub repo
```sh
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj-labs/argocd-image-updater/stable/manifests/install.yaml
```

Create secret for ArgoCD image updater to have access to your DockerHub repo
```sh
kubectl create -n argocd secret docker-registry dockerhub-secret \
  --docker-username someuser \
  --docker-password s0m3p4ssw0rd \
  --docker-email abc@example.com \
  --docker-server "https://registry-1.docker.io"
```

Update Argocd image updater config map
```sh
kubectl edit cm -n argocd argocd-image-updater-config
```

And add data to use your DockerHub repo with your creds
```sh
data:
  log.level: debug
  registries.conf: |
    registries:
    - name: Docker Hub
      prefix: docker.io
      api_url: https://registry-1.docker.io
      credentials: pullsecret:argocd/dockerhub-secret
      defaultns: denisdugar
      default: true
```

Add your git credentials for ArgoCd Image updater can update your GitHub repo
```sh
kubectl create secret generic image-updater-git-cred \
  --namespace=argocd \
  --from-literal=url=https://github.com/denisdugar/ci-cd-tutorial-sample-app.git \
  --from-literal=username=denisdugar \
  --from-literal=password=<github_token> \
  --labels=argocd.argoproj.io/secret-type=repository
```

Restart argocd-image-updater deploy for applying updates
```sh
kubectl -n argocd rollout restart deployment argocd-image-updater
```

And you can check logs if there are some errors
```sh
kubectl logs -n argocd deployment/argocd-image-updater -f
```

##
Now your infrastructure is ready. Every time someone will push updates to the repo it will run Jenkins pipeline update DockerHub repo and ArgoCD image updater will check that and update kustomization file with new image tag. After that ArgoCD will update your current EKS infrastructure with new image.


## Infrastructure diagram 
![k8s_argocd drawio (2)](https://github.com/user-attachments/assets/06696961-a9cb-4af9-ac1d-8882f262852e)

