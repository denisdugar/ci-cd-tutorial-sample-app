#!/bin/bash
sudo apt update
sudo apt install fontconfig openjdk-21-jre -y
sudo wget -O /etc/apt/keyrings/jenkins-keyring.asc https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key
echo "deb [signed-by=/etc/apt/keyrings/jenkins-keyring.asc]" https://pkg.jenkins.io/debian-stable binary/ | sudo tee /etc/apt/sources.list.d/jenkins.list > /dev/null
sudo apt-get update
sudo apt-get install jenkins -y
sudo systemctl enable jenkins
sed -i 's/-Djava.net.preferIPv4Stack=true/-Djava.net.preferIPv4Stack=true -Djenkins.install.runSetupWizard=false/g' /etc/default/jenkins
echo "2.0" > /var/lib/jenkins/jenkins.install.UpgradeWizard.state
mkdir /var/lib/jenkins/init.groovy.d
sudo apt install unzip
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
aws ssm get-parameter \
    --name "${parameter}" \
    --with-decryption \
    --query "Parameter.Value" \
    --output text > /var/lib/jenkins/init.groovy.d/basic-security.groovy
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo service docker start
sudo groupadd docker
sudo usermod -aG docker jenkins
newgrp docker
sudo apt install -y jq
sudo systemctl restart jenkins
wget http://localhost:8080/jnlpJars/jenkins-cli.jar
secret_json=$(aws secretsmanager get-secret-value --secret-id ${secret} --query SecretString --output text)
username=$(echo "$secret_json" | jq -r .username)
password=$(echo "$secret_json" | jq -r .password)
java -jar jenkins-cli.jar -auth $username:$password -s http://localhost:8080/ install-plugin docker-workflow
java -jar jenkins-cli.jar -auth $username:$password -s http://localhost:8080/ install-plugin docker-plugin
java -jar jenkins-cli.jar -auth $username:$password -s http://localhost:8080/ install-plugin pyenv-pipeline
java -jar jenkins-cli.jar -auth $username:$password -s http://localhost:8080/ install-plugin workflow-aggregator
java -jar jenkins-cli.jar -auth $username:$password -s http://localhost:8080/ install-plugin git
sudo systemctl restart jenkins
