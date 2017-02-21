
properties([
  [$class: 'ParametersDefinitionProperty', parameterDefinitions: [
    [$class: 'StringParameterDefinition', defaultValue: '', description: 'The git branch to build', name: 'GIT_BRANCH'],
    [$class: 'StringParameterDefinition', defaultValue: 'latest', description: 'The docker image tag', name: 'IMAGE_TAG']
  ]]
])

node('master') {
  try {
    notifyStarted()
    currentBuild.displayName = "${BUILD_NUMBER}-bluegreen1"
    currentBuild.description = "Aceinfo Automation"
    wrap([$class: 'BuildUser']) {
      def oc = "oc"
      def osHost = "ocpc.gitook.com:8443"
      def osCredentialId = 'OpenshiftCredentialId'
      def gitUrl = 'https://github.com/aceinfo-jenkins/bluegreen1.git'
      def gitCredentialId = 'jenkinsGithubCredentialId'
      def nexusRegistry = "nexus.gitook.com:8447/demouser"
      def nexusCredentialId = '41aebb46-b195-4957-bae0-78376aa149b0'
      def testingTemplateName = "templates/testing-template.yaml"
      def testingProject = "testing"

      stage ('Preparation') {
        checkout([$class: 'GitSCM',
          branches: [[name: "${GIT_BRANCH}"]],
          doGenerateSubmoduleConfigurations: false,
          extensions: [],
          submoduleCfg: [],
          userRemoteConfigs: [[credentialsId: gitCredentialId, url: gitUrl]],
  	poll: true
        ])
        dir("${env.WORKSPACE}") {
          sh """
            ./gradlew clean
          """
        }
      }

      stage('Build') {
        hygieiaBuildPublishStep buildStatus: 'InProgress'
        dir("${env.WORKSPACE}") {
          sh """
            ./gradlew build
          """
        }
        slackSend (color: '#FFFF00', message: "BUILD STARTED : Job '${env.JOB_NAME} [${env.BUILD_NUMBER}]' (${env.BUILD_URL})")
      }

      stage('Unit Testing') {
         sh """
          ./gradlew clean test
          #hygieiaTestPublishStep buildStatus: 'Success', testApplicationName: 'bluegreen1', testEnvironmentName: 'CI', testFileNamePattern: '*.html', testResultsDirectory: '/src/cheersApp/build/reports/tests/test/', testType: 'Unit'
         """
      }

      stage('Static Code Analysis - findBugs') {
        dir("${env.WORKSPACE}") {
          sh """
            ./gradlew check
          """
        }
      }

      stage('Code Quality - SonarQube') {
        dir("${env.WORKSPACE}") {
          sh """
            ./gradlew sonarqube -Dsonar.host.url=http://sonar.gitook.com:9000
          """
         hygieiaSonarPublishStep ceQueryIntervalInSeconds: '10', ceQueryMaxAttempts: '30'
        }
      }

      stage ('Compose Docker Image') {
        //input message: "Continue Build Docker Image?", ok: "Build"
        dir("${env.WORKSPACE}") {
          sh """
             ./gradlew buildDocker
          """
        }
      }

      stage('Publish Docker Image') {
        step([$class:'FindBugsPublisher', canComputeNew:false, pattern:'**/findbugs/*.xml'])
        archiveArtifacts artifacts: 'build/libs/*.jar', onlyIfSuccessful: true
        archiveArtifacts artifacts: 'build/test-results/**/*', onlyIfSuccessful: false
        step([$class: 'JUnitResultArchiver', testResults: 'build/test-results/test/TEST-*.xml'])

        withCredentials([
          [$class: 'UsernamePasswordMultiBinding', credentialsId: nexusCredentialId, usernameVariable: 'NEXUS_USERNAME', passwordVariable: 'NEXUS_PASSWORD']
        ]) {
          dir("${env.WORKSPACE}") {
            sh """
               docker login nexus.gitook.com:8447 --username ${env.NEXUS_USERNAME} --password ${env.NEXUS_PASSWORD}
               docker tag demouser/bluegreen1:latest nexus.gitook.com:8447/demouser/bluegreen1:${IMAGE_TAG}
               docker push nexus.gitook.com:8447/demouser/bluegreen1:${IMAGE_TAG}
               docker rmi demouser/bluegreen1:latest
            """
          }
        }
      }

     stage ('Deploy to Testing Environment') {
        //input message: "Deploy Image to Openshift?", ok: "Deploy"
        withCredentials([
          [$class: 'UsernamePasswordMultiBinding', credentialsId: osCredentialId, usernameVariable: 'OS_USERNAME', passwordVariable: 'OS_PASSWORD'],
          [$class: 'UsernamePasswordMultiBinding', credentialsId: nexusCredentialId, usernameVariable: 'NEXUS_USERNAME', passwordVariable: 'NEXUS_PASSWORD']
        ]) {
          sh """
            ${oc} login ${osHost} --username=${env.OS_USERNAME} --password=${env.OS_PASSWORD} --insecure-skip-tls-verify
          """

          try {
            sh """
              ${oc} project ${testingProject}
            """         
          } catch (Exception e) {
            sh """
              ${oc} new-project ${testingProject} --display-name="Testing Environment"
              ${oc} secrets new-dockercfg "nexus-${testingProject}" --docker-server=${nexusRegistry} \
                --docker-username="${env.NEXUS_USERNAME}" --docker-password="${env.NEXUS_PASSWORD}" --docker-email="docker@gitook.com"
              ${oc} secrets link default "nexus-${testingProject}" --for=pull
              ${oc} secrets link builder "nexus-${testingProject}" --for=pull
              ${oc} secrets link deployer "nexus-${testingProject}" --for=pull
            """                
          }
          sh """
            ${oc} process -f ${testingTemplateName} | ${oc} create -f - -n ${testingProject} || true
            ${oc} tag --source=docker ${nexusRegistry}/bluegreen1:${IMAGE_TAG} ${testingProject}/bluegreen1-is:latest --insecure
            sleep 5
            ${oc} import-image bluegreen1-is --confirm --insecure | grep -i "successfully"

            echo "Liveness check URL: http://`${oc} get route bluegreen1-rt -n ${testingProject} -o jsonpath='{ .spec.host }'`/bluegreen1"
          """
        }
      }

      stage('API/Intgration Testing') {
  /*    
        timeout (time: 5, unit: 'MINUTES') {
          sh """
            REVAL=1
            while [ \$REVAL ]
            do
              sleep 10
              curl -I "http://`${oc} get route hello10-rt -n ${testingProject} -o jsonpath='{ .spec.host }'`/hello-world" | grep "HTTP/1.1 200"
              REVAL=\$?
            done
          """
        }
  */
      }

      stage('Performance Testing - jMeter') {
        dir("${env.WORKSPACE}") {
          echo "jMeter..."
        }
      }

      stage ('Destroy FT Environment in Openshift') {
        //input message: "Delete Openshift Environment(Cleanup)?", ok: "Delete"

        withCredentials([
          [$class: 'UsernamePasswordMultiBinding', credentialsId: osCredentialId, usernameVariable: 'OS_USERNAME', passwordVariable: 'OS_PASSWORD']
        ]) {
          sh """
            ${oc} login ${osHost} --username=${env.OS_USERNAME} --password=${env.OS_PASSWORD} --insecure-skip-tls-verify
            ${oc} delete project ${testingProject}
            ${oc} logout
          """
        }
      }

      stage('Merge CI Branch to Master') {
         withCredentials([
          [$class: 'UsernamePasswordMultiBinding', credentialsId: gitCredentialId, usernameVariable: 'GIT_USERNAME', passwordVariable: 'GIT_PASSWORD']
        ]) {
          dir("${env.WORKSPACE}") {
            sh """
              git remote set-url origin "https://${env.GIT_USERNAME}:${env.GIT_PASSWORD}@github.com/${env.GIT_USERNAME}/bluegreen1.git"
              git push origin HEAD:master
            """
          }
        }
      }

    }

    notifySuccessful()

  } catch (e) {
    currentBuild.result = "FAILED"
    notifyFailed()
    throw e
  }
}

def notifyStarted() {
  // send to Slack
  slackSend (color: '#FFFF00', message: "STARTED: Job '${env.JOB_NAME} [${env.BUILD_NUMBER}]' (${env.BUILD_URL})")

  // send to HipChat
  //hipchatSend (color: 'YELLOW', notify: true,
  //    message: "STARTED: Job '${env.JOB_NAME} [${env.BUILD_NUMBER}]' (${env.BUILD_URL})"
  //  )

  // send to email
  emailext (
      subject: "STARTED: Job '${env.JOB_NAME} [${env.BUILD_NUMBER}]'",
      body: """<p>STARTED: Job '${env.JOB_NAME} [${env.BUILD_NUMBER}]':</p>
        <p>Check console output at &QUOT;<a href='${env.BUILD_URL}'>${env.JOB_NAME} [${env.BUILD_NUMBER}]</a>&QUOT;</p>""",
      recipientProviders: [[$class: 'DevelopersRecipientProvider']]
    )
}
def notifySuccessful() {
  slackSend (color: '#00FF00', message: "SUCCESSFUL: Job '${env.JOB_NAME} [${env.BUILD_NUMBER}]' (${env.BUILD_URL})")

  //hipchatSend (color: 'GREEN', notify: true,
  //    message: "SUCCESSFUL: Job '${env.JOB_NAME} [${env.BUILD_NUMBER}]' (${env.BUILD_URL})"
  //  )

  emailext (
      subject: "SUCCESSFUL: Job '${env.JOB_NAME} [${env.BUILD_NUMBER}]'",
      body: """<p>SUCCESSFUL: Job '${env.JOB_NAME} [${env.BUILD_NUMBER}]':</p>
        <p>Check console output at &QUOT;<a href='${env.BUILD_URL}'>${env.JOB_NAME} [${env.BUILD_NUMBER}]</a>&QUOT;</p>""",
      recipientProviders: [[$class: 'DevelopersRecipientProvider']]
    )
}

def notifyFailed() {
  slackSend (color: '#FF0000', message: "FAILED: Job '${env.JOB_NAME} [${env.BUILD_NUMBER}]' (${env.BUILD_URL})")

  //hipchatSend (color: 'RED', notify: true,
  //    message: "FAILED: Job '${env.JOB_NAME} [${env.BUILD_NUMBER}]' (${env.BUILD_URL})"
  //  )

  emailext (
      subject: "FAILED: Job '${env.JOB_NAME} [${env.BUILD_NUMBER}]'",
      body: """<p>FAILED: Job '${env.JOB_NAME} [${env.BUILD_NUMBER}]':</p>
        <p>Check console output at &QUOT;<a href='${env.BUILD_URL}'>${env.JOB_NAME} [${env.BUILD_NUMBER}]</a>&QUOT;</p>""",
      recipientProviders: [[$class: 'DevelopersRecipientProvider']]
    )
}
