#!/bin/bash
# update and install jenkins
sudo apt-get update
sudo apt-get install fontconfig openjdk-21-jre -y
sudo wget -O /etc/apt/keyrings/jenkins-keyring.asc https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key
echo "deb [signed-by=/etc/apt/keyrings/jenkins-keyring.asc]" https://pkg.jenkins.io/debian-stable binary/ | sudo tee /etc/apt/sources.list.d/jenkins.list > /dev/null
sudo apt-get update
sudo apt-get install jenkins -y
sudo systemctl enable jenkins


# disable SetubWizard for Jenkins to skip first setup
sed -i 's/-Djava.net.preferIPv4Stack=true/-Djava.net.preferIPv4Stack=true -Djenkins.install.runSetupWizard=false/g' /etc/default/jenkins


# add version to use groovy scripts
echo "2.0" > /var/lib/jenkins/jenkins.install.UpgradeWizard.state


# create directory for user creation script
mkdir /var/lib/jenkins/init.groovy.d


# install awscli
sudo apt install unzip
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install


# get script for creating Jenkins user from AWS SSM Parameter Store and add to newly created directory
aws ssm get-parameter \
    --name "${parameter}" \
    --with-decryption \
    --query "Parameter.Value" \
    --output text > /var/lib/jenkins/init.groovy.d/basic-security.groovy


# install docker and add Jenkins user to use docker commands
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo service docker start
sudo groupadd docker
sudo usermod -aG docker jenkins
newgrp docker
sudo apt install -y jq


# restart jenkins to apply new user and new configuration
sudo systemctl restart jenkins


# install jenkins cli for installing plugins
wget http://localhost:8080/jnlpJars/jenkins-cli.jar


# get jenkins credentials srom AWS Secret Manager
secret_json=$(aws secretsmanager get-secret-value --secret-id ${secret} --query SecretString --output text)
username=$(echo "$secret_json" | jq -r .username)
password=$(echo "$secret_json" | jq -r .password)


# install plugins
java -jar jenkins-cli.jar -auth $username:$password -s http://localhost:8080/ install-plugin docker-workflow
java -jar jenkins-cli.jar -auth $username:$password -s http://localhost:8080/ install-plugin docker-plugin
java -jar jenkins-cli.jar -auth $username:$password -s http://localhost:8080/ install-plugin pyenv-pipeline
java -jar jenkins-cli.jar -auth $username:$password -s http://localhost:8080/ install-plugin workflow-aggregator
java -jar jenkins-cli.jar -auth $username:$password -s http://localhost:8080/ install-plugin git
java -jar jenkins-cli.jar -auth $username:$password -s http://localhost:8080/ install-plugin github


# restart jenkins to apply all changes
sudo systemctl restart jenkins
