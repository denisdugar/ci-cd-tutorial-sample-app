pipeline {
    agent any // This specifies that the pipeline can run on any available agent
        }
        stage('Build Docker Image') {
            steps {
                script {
                    sh "ls"
                    // Defining the image name with tag
                    def dockerImageName = 'app:lts'

                    // Building the Docker image
                    sh "docker build -t ${dockerImageName} ."

                    // Optionally, you can push the image to a registry
                    // sh "docker push ${dockerImageName}"
                }
            }
        }
    }
}

