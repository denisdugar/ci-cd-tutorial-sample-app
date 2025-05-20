[![Quality Gate Status](https://sonarcloud.io/api/project_badges/measure?project=denisdugar_ci-cd-tutorial-sample-app&metric=alert_status)](https://sonarcloud.io/summary/new_code?id=denisdugar_ci-cd-tutorial-sample-app)
[![Build Status](http://jenkins-alb-445339980.us-east-1.elb.amazonaws.com/job/Test/badge/icon)](http://jenkins-alb-445339980.us-east-1.elb.amazonaws.com/job/Test)
# CICD AWS EKS infrastructure

## Pre-requirements
Terraform v1.10.3
 
aws-cli v2.23.13

eksctl v0.203.0

kubectl v1.32.1

User in AWS with policies for creating all needed resources.
##
In AWS console, please create a secret in Secrets Manager with the username and password you will be using for Jenkins:
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

In the infra directory, run the terraform commands to create the network infrastructure for Jenkins and EKS cluster, and create a Jenkins instance
```sh
terraform init
terraform apply --auto-approve
```

After all resources are created, wait 5-10 minutes for the user-data script to finish. Open AWS console and go to Load Balancers. Take the newly created Load Balancer URL. This is URL for your Jenkins. Your credentials are the same you paste in the script before.

Log in to your account, go to Managed Jenkins -> Credentials -> Global, and create DockerHub credentials for your DockerHub account. Create one with the ID "dockerhub_id." It will be used in the pipeline. Also, add a Sonar Cloud token and call it SONAR_TOKEN. Switch on anonymous view in Managed Jenkins -> Security for Jenkins badge is working in GitHub. (Check this badge and change URL and job name if it's needed)

After that, you can go to + New Item and create 2 pipelines
1. PyTest - testing python code (Jenkinsfile_pytest)
2. DockerBuild - build and push Docker image to your DockerHub (Jenkinsfile_build_docker)
   For changing the default DockerHub repo, please change it in Jenkinsfile_build_docker file

PyTest pipeline should work anytime some updates are pushed to the GitHub repo. Add this trigger in the pipeline and create a webhook in the settings of the GitHub repo
The link should look like:
```sh
http://<jenkins_server>/github-webhook/
```
Disable ssl and choose Just the push event

After all this setup, you can go to the infra directory. Take outputs from the terraform command with the vpc and subnet IDs and put them in to cluster.yaml file. 
Now you can run
```sh
eksctl create cluster -f cluster.yaml
```
It will take 10-30 minutes and create EKS cluster in AWS.

After EKS cluster is created, use 
```sh
docker login
```
to log in to your Docker account. It will create /home/user/.docker/config.json with your Docker credentials.
We will use it to create Kubernetes secret for pulling an image from your private Docker repo

```sh
kubectl create secret generic regcred \
  --from-file=.dockerconfigjson=/home/user/.docker/config.json \
  --type=kubernetes.io/dockerconfigjson
```

Apply kustomization file to create the deployment and service. (Choose an image for your repo)
```sh
kubectl apply -k .
```

Now we can add ArgoCD to EKS cluster, run those commands, and create a LoadBalancer to reach the ArgoCD UI
```sh
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "LoadBalancer"}}'
```

Install ArgoCD CLI
```sh
curl -sSL -o argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
chmod +x argocd
sudo mv argocd /usr/local/bin/
```

Use this command to get the admin password for logging into ArgoCD
```sh
argocd admin initial-password -n argocd
```

Use kubectl to get the LoadBalancer URL for ArgoCD
```sh
kubectl get service -n argocd
```

Add ArgoCD notifications
```sh
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/notifications_catalog/install.yaml
```

Patch the secret with credentials to your mail that you will use to notify someone
```sh
kubectl patch secret argocd-notifications-secret \
  -n argocd \
  --type merge \
  --patch '{
    "stringData": {
      "email-username": "someuser@gmail.com",
      "email-password": "<YOUR_APP_PASSWORD>"
    }
  }'
```

Patch the Config Map with creds for mail
```sh
kubectl patch cm argocd-notifications-cm -n argocd --type merge -p '{"data": {"service.email.gmail": "{ username: $email-username, password: $email-password, host: smtp.gmail.com, port: 465, from: $email-username }" }}'
```

Change the email in application.yaml file for your own. You will be receiving notifications to this mail

Create an application in ArgoCD, use this command (change image)
```sh
kubectl apply -f application.yaml
```

Let's add ArgoCD image updater to our cluster to automatically update the repo and deploy if a new version appears in the DockerHub repo
```sh
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj-labs/argocd-image-updater/stable/manifests/install.yaml
```

Create a secret for ArgoCD image updater to have access to your DockerHub repo
```sh
kubectl create -n argocd secret docker-registry dockerhub-secret \
  --docker-username someuser \
  --docker-password s0m3p4ssw0rd \
  --docker-email abc@example.com \
  --docker-server "https://registry-1.docker.io"
```

Update ArgoCD image updater config map
```sh
kubectl edit cm -n argocd argocd-image-updater-config
```

And add data to use your DockerHub repo with your credentials
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

Add your git credentials for the ArgoCD Image updater can update your GitHub repo
```sh
kubectl create secret generic image-updater-git-cred \
  --namespace=argocd \
  --from-literal=url=<git_repo_url> \
  --from-literal=username=<git_username> \
  --from-literal=password=<github_token>

kubectl label secret image-updater-git-cred \
  --namespace=argocd \
  argocd.argoproj.io/secret-type=repository
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
Now your infrastructure is ready. Every time someone pushes updates to the repo, it will run Jenkins pipeline update DockerHub repo, and the ArgoCD image updater will check that and update kustomization file with the new image tag. After that, ArgoCD will update your current EKS infrastructure with the new image.


## Infrastructure diagram 
![k8s_argocd drawio (3)](https://github.com/user-attachments/assets/5968237c-72f6-4236-84d0-eea555b36d30)
