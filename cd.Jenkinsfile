
properties([
  [$class: 'ParametersDefinitionProperty', parameterDefinitions: [
    [$class: 'StringParameterDefinition', defaultValue: 'latest', description: 'The docker image tag', name: 'IMAGE_TAG'],
  ]]
])

node('master') {
  def oc = "oc"
  def osHost = "ocpc.gitook.com:8443"
  def osCredentialId = 'OpenshiftCredentialId'
  def gitUrl = 'https://github.com/aceinfo-jenkins/bluegreen1.git'
  def gitCredentialId = 'jenkinsGithubCredentialId'
  def dockerRegistry = "nexus.gitook.com:8447/demouser"
  def nexusCredentialId = '41aebb46-b195-4957-bae0-78376aa149b0'
  def stagingProject = "staging"
  def productionProject = "production"
  def stagingTemplate = "templates/staging-template.yaml"
  def productionTemplate = "templates/production-template.yaml"
  def green = "a"
  def blue = "b"
  def userInput
  def blueWeight
  def greenWeight
  def abDeployment = false

  try {
    notifyStarted()

    stage ('Preparation') {
      checkout([$class: 'GitSCM',
        branches: [[name: '*/master']],
        doGenerateSubmoduleConfigurations: false,
        extensions: [],
        submoduleCfg: [],
        userRemoteConfigs: [[credentialsId: gitCredentialId, url: gitUrl]]
      ])
    }

    stage ('Initializing OCP PAAS') {
      withCredentials([
        [$class: 'UsernamePasswordMultiBinding', credentialsId: osCredentialId, usernameVariable: 'OS_USERNAME', passwordVariable: 'OS_PASSWORD'],
        [$class: 'UsernamePasswordMultiBinding', credentialsId: nexusCredentialId, usernameVariable: 'NEXUS_USERNAME', passwordVariable: 'NEXUS_PASSWORD']
      ]) {
        sh """
          ${oc} login ${osHost} --username=${env.OS_USERNAME} --password=${env.OS_PASSWORD} --insecure-skip-tls-verify
        """
        try {
          sh """
            ${oc} project ${stagingProject}
          """         
        } catch (Exception e) {
          sh """
            ${oc} new-project ${stagingProject} --display-name="Staging Environment"
            ${oc} secrets new-dockercfg "nexus-${stagingProject}" --docker-server=${dockerRegistry} \
              --docker-username="${env.NEXUS_USERNAME}" --docker-password="${env.NEXUS_PASSWORD}" --docker-email="docker@gitook.com"
            ${oc} secrets link default "nexus-${stagingProject}" --for=pull
            ${oc} secrets link builder "nexus-${stagingProject}" --for=pull
            ${oc} secrets link deployer "nexus-${stagingProject}" --for=pull
          """                
        }

        try {
          sh """
            ${oc} project ${productionProject}
          """         
        } catch (Exception e) {
          sh """
            ${oc} new-project ${productionProject} --display-name="Production Environment"
            ${oc} secrets new-dockercfg "nexus-${productionProject}" --docker-server=${dockerRegistry} \
              --docker-username="${env.NEXUS_USERNAME}" --docker-password="${env.NEXUS_PASSWORD}" --docker-email="docker@gitook.com"
            ${oc} secrets link default "nexus-${productionProject}" --for=pull
            ${oc} secrets link builder "nexus-${productionProject}" --for=pull
            ${oc} secrets link deployer "nexus-${productionProject}" --for=pull
          """                
        }
      }
    }
    
    stage ('Staging Deployment') {
      withCredentials([
        [$class: 'UsernamePasswordMultiBinding', credentialsId: osCredentialId, usernameVariable: 'OS_USERNAME', passwordVariable: 'OS_PASSWORD'],
      ]) {
        sh """
          ${oc} login ${osHost} -n ${stagingProject} --username=${env.OS_USERNAME} --password=${env.OS_PASSWORD} --insecure-skip-tls-verify
          ${oc} process -f ${stagingTemplate} | ${oc} create -f - -n ${stagingProject} || true

          ${oc} tag --source=docker ${dockerRegistry}/bluegreen1:${IMAGE_TAG} ${stagingProject}/bluegreen1-is:latest --insecure
          sleep 5
          ${oc} import-image bluegreen1-is --confirm --insecure | grep -i "successfully"

          echo "Liveness check URL: http://`oc get route bluegreen1-rt -n ${stagingProject} -o jsonpath='{ .spec.host }'`/bluegreen1"
        """
      }
    }

    stage ('ZDD Production Deployment') {
      userInput = input(
         id: 'userInput', message: 'ZDD A/B deployment or ZDD Rolling deployment?', parameters: [
          [$class: 'ChoiceParameterDefinition', choices: 'ZDD A/B deployment\nZDD Rolling Deployment', description: 'ZDD A/B(inlcuding Blue/Green) Deployment or ZDD Rolling Deployment', name: 'DEPLOYMENT_TYPE'],
         ])
      withCredentials([
        [$class: 'UsernamePasswordMultiBinding', credentialsId: osCredentialId, usernameVariable: 'OS_USERNAME', passwordVariable: 'OS_PASSWORD']
      ]) {
        sh """
          ${oc} login ${osHost} -n ${productionProject} --username=${env.OS_USERNAME} --password=${env.OS_PASSWORD} --insecure-skip-tls-verify
          ${oc} process -f ${productionTemplate} | oc create -f - -n ${productionProject} || true

          ${oc} get route ab-bluegreen1-rt -n ${productionProject} -o jsonpath='{ .spec.to.name }' > active_service.txt
          cat active_service.txt
        """
        activeService = readFile('active_service.txt').trim()
        if (activeService == "a-bluegreen1-svc") {
          blue = "a"
          green = "b"
        }

        if (userInput == "ZDD Rolling Deployment") {
          sh """
            ${oc} tag --source=docker ${ockerRegistry}/bluegreen1:${IMAGE_TAG} ${productionProject}/${blue}-bluegreen1-is:latest --insecure
            sleep 5
            ${oc} import-image ${blue}-bluegreen1-is --confirm --insecure -n ${productionProject} | grep -i "successfully"
            ${oc} set -n ${productionProject} route-backends ab-bluegreen1-rt ${blue}-bluegreen1-svc=100 ${green}-bluegreen1-svc=0
            echo "Application liveness check URL: http://`oc get route ab-bluegreen1-rt -n ${productionProject} -o jsonpath='{ .spec.host }'`/bluegreen1"
          """
        } else {
          abDeployment = true
          sh """
            ${oc} tag --source=docker ${dockerRegistry}/bluegreen1:${IMAGE_TAG} ${productionProject}/${green}-bluegreen1-is:latest --insecure
            sleep 5
            ${oc} import-image ${green}-bluegreen1-is --confirm --insecure -n ${productionProject} | grep -i "successfully"
            echo "Green liveness check URL: http://`oc get route ${green}-bluegreen1-rt -n ${productionProject} -o jsonpath='{ .spec.host }'`/bluegreen1"
          """
        }
      }
    }
    if (abDeployment) {
      stage ('Production ZDD Canary Deployment') {
        userInput = input(
         id: 'userInput', message: 'Production ZDD Canary Deployment?', parameters: [
            [$class: 'StringParameterDefinition', defaultValue: '10', description: 'Green(Newly deployed) weight', name: 'GREEN_WEIGHT'],
            [$class: 'StringParameterDefinition', defaultValue: '90', description: 'Blue(Existing deployment) weight', name: 'BLUE_WEIGHT'],
           ])
        blueWeight = userInput['BLUE_WEIGHT']
        greenWeight = userInput['GREEN_WEIGHT']
        withCredentials([
          [$class: 'UsernamePasswordMultiBinding', credentialsId: osCredentialId, usernameVariable: 'OS_USERNAME', passwordVariable: 'OS_PASSWORD']
        ]) {
          sh """
            ${oc} login ${osHost} -n ${productionProject} --username=${env.OS_USERNAME} --password=${env.OS_PASSWORD} --insecure-skip-tls-verify
            ${oc} set -n ${productionProject} route-backends ab-bluegreen1-rt ${green}-bluegreen1-svc=${greenWeight} ${blue}-bluegreen1-svc=${blueWeight}
            echo "Green liveness check URL: http://`oc get route ${green}-bluegreen1-rt -n ${productionProject} -o jsonpath='{ .spec.host }'`/bluegreen1"
            echo "Blue liveness check URL: http://`oc get route ${blue}-bluegreen1-rt -n ${productionProject} -o jsonpath='{ .spec.host }'`/bluegreen1"
            echo "Application liveness check URL: http://`oc get route ab-bluegreen1-rt -n ${productionProject} -o jsonpath='{ .spec.host }'`/bluegreen1"
          """
        }
      }

      stage ('Production ZDD Go Live or Rollback') {
        userInput = input(
           id: 'userInput', message: 'Production ZDD Go Live or ZDD Rollback?', parameters: [
            [$class: 'ChoiceParameterDefinition', choices: 'ZDD Go Live\nZDD Rollback', description: 'ZDD Go Live to Green or ZDD Rollback to Blue', name: 'GO_LIVE_OR_ROLLBACK'],
           ])
        withCredentials([
          [$class: 'UsernamePasswordMultiBinding', credentialsId: osCredentialId, usernameVariable: 'OS_USERNAME', passwordVariable: 'OS_PASSWORD']
        ]) {
          sh """
            ${oc} login ${osHost} -n ${productionProject} --username=${env.OS_USERNAME} --password=${env.OS_PASSWORD} --insecure-skip-tls-verify
          """

          if (userInput == "ZDD Rollback") {
            sh """
              ${oc} set -n ${productionProject} route-backends ab-bluegreen1-rt ${blue}-bluegreen1-svc=100 ${green}-bluegreen1-svc=0
            """              
          } else {
            sh """
              ${oc} set -n ${productionProject} route-backends ab-bluegreen1-rt ${green}-bluegreen1-svc=100 ${blue}-bluegreen1-svc=0
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
