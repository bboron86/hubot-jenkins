# Description:
#   Interact with your Jenkins CI server
#
# Dependencies:
#   None
#
# Configuration:
#   HUBOT_JENKINS_URL
#   HUBOT_JENKINS_AUTH
#
#   Auth should be in the "user:password" format.
#
# Commands:
#   hubot jenkins b <jobNumber> - builds the job specified by jobNumber. List jobs to get number.
#   hubot jenkins build <job> - builds the specified Jenkins job
#   hubot jenkins build <job>, <params> - builds the specified Jenkins job with parameters as key=value&key2=value2
#   hubot jenkins list <filter> - lists Jenkins jobs (BB)
#   hubot jenkins describe <job> - Describes the specified Jenkins job
#   hubot jenkins last <job> - Details about the last build for the specified Jenkins job

#
# Author:
#   dougcole

querystring = require 'querystring'
Conversation = require 'hubot-conversation'

# Holds a list of jobs, so we can trigger them with a number
# instead of the job's name. Gets populated on when calling
# list.
jobList = []

jenkinsBuildById = (msg) ->
  # Switch the index with the job name
  job = jobList[parseInt(msg.match[1]) - 1]

  if job
    msg.match[1] = job
    jenkinsBuild(msg)
  else
    msg.reply "Sorry, I don't know this job!"

jenkinsBuild = (msg, buildWithEmptyParameters) ->
    url = process.env.HUBOT_JENKINS_URL
    unescapedJob = msg.match[1]
    job = querystring.escape unescapedJob
    params = msg.match[3]
    command = if buildWithEmptyParameters then "buildWithParameters" else "build"
    path = if params then "#{url}/job/#{job}/buildWithParameters?#{params}" else "#{url}/job/#{job}/#{command}"

    req = msg.http(path)

    if process.env.HUBOT_JENKINS_AUTH
      auth = new Buffer(process.env.HUBOT_JENKINS_AUTH).toString('base64')
      req.headers Authorization: "Basic #{auth}"

    req.header('Content-Length', 0)
    req.post() (err, res, body) ->
        if err
          msg.reply "Jenkins says: #{err}"
        else if 200 <= res.statusCode < 400 # Or, not an error code.
          msg.reply "Build started for '#{unescapedJob}' #{url}/job/#{job}"
        else if 400 == res.statusCode
          jenkinsBuild(msg, true)
        else
          msg.reply "Jenkins says: Status #{res.statusCode} #{body}"

jenkinsDescribe = (msg) ->
    url = process.env.HUBOT_JENKINS_URL
    job = msg.match[1]

    path = "#{url}/job/#{job}/api/json"

    req = msg.http(path)

    if process.env.HUBOT_JENKINS_AUTH
      auth = new Buffer(process.env.HUBOT_JENKINS_AUTH).toString('base64')
      req.headers Authorization: "Basic #{auth}"

    req.header('Content-Length', 0)
    req.get() (err, res, body) ->
        if err
          msg.send "Jenkins says: #{err}"
        else
          response = ""
          try
            content = JSON.parse(body)
            response += "JOB: #{content.displayName}\n"
            response += "URL: #{content.url}\n"

            if content.description
              response += "DESCRIPTION: #{content.description}\n"

            response += "ENABLED: #{content.buildable}\n"
            response += "STATUS: #{content.color}\n"

            tmpReport = ""
            if content.healthReport.length > 0
              for report in content.healthReport
                tmpReport += "\n  #{report.description}"
            else
              tmpReport = " unknown"
            response += "HEALTH: #{tmpReport}\n"

            parameters = ""
            for item in content.actions
              if item.parameterDefinitions
                for param in item.parameterDefinitions
                  tmpDescription = if param.description then " - #{param.description} " else ""
                  tmpDefault = if param.defaultParameterValue then " (default=#{param.defaultParameterValue.value})" else ""
                  parameters += "\n  #{param.name}#{tmpDescription}#{tmpDefault}"

            if parameters != ""
              response += "PARAMETERS: #{parameters}\n"

            msg.send response

            if not content.lastBuild
              return

            path = "#{url}/job/#{job}/#{content.lastBuild.number}/api/json"
            req = msg.http(path)
            if process.env.HUBOT_JENKINS_AUTH
              auth = new Buffer(process.env.HUBOT_JENKINS_AUTH).toString('base64')
              req.headers Authorization: "Basic #{auth}"

            req.header('Content-Length', 0)
            req.get() (err, res, body) ->
                if err
                  msg.send "Jenkins says: #{err}"
                else
                  response = ""
                  try
                    content = JSON.parse(body)
                    console.log(JSON.stringify(content, null, 4))
                    jobstatus = content.result || 'PENDING'
                    jobdate = new Date(content.timestamp);
                    response += "LAST JOB: #{jobstatus}, #{jobdate}\n"

                    msg.send response
                  catch error
                    msg.send error

          catch error
            msg.send error

jenkinsLast = (msg) ->
    url = process.env.HUBOT_JENKINS_URL
    job = msg.match[1]

    path = "#{url}/job/#{job}/lastBuild/api/json"

    req = msg.http(path)

    if process.env.HUBOT_JENKINS_AUTH
      auth = new Buffer(process.env.HUBOT_JENKINS_AUTH).toString('base64')
      req.headers Authorization: "Basic #{auth}"

    req.header('Content-Length', 0)
    req.get() (err, res, body) ->
        if err
          msg.send "Jenkins says: #{err}"
        else
          response = ""
          try
            content = JSON.parse(body)
            response += "NAME: #{content.fullDisplayName}\n"
            response += "URL: #{content.url}\n"

            if content.description
              response += "DESCRIPTION: #{content.description}\n"

            response += "BUILDING: #{content.building}\n"

            msg.send response

jenkinsList = (msg) ->
    url = process.env.HUBOT_JENKINS_URL
    filter = new RegExp(msg.match[2], 'i')
    req = msg.http("#{url}/api/json")

    if process.env.HUBOT_JENKINS_AUTH
      auth = new Buffer(process.env.HUBOT_JENKINS_AUTH).toString('base64')
      req.headers Authorization: "Basic #{auth}"

    req.get() (err, res, body) ->
        response = "Ok, here are jobs I found available to trigger deployment: \n"
        if err
          msg.send "Jenkins says: #{err}"
        else
          try
            content = JSON.parse(body)
            for jobFromServer in content.jobs
              # Add new jobs to the jobList (if passed the filter)
              if filter.test jobFromServer.name
                jobList.push(jobFromServer.name) if jobList.indexOf(jobFromServer.name) is -1

            content.jobs.sort (a, b) ->
              aIndex = jobList.indexOf a.name
              bIndex = jobList.indexOf b.name
              aIndex - bIndex
            .forEach (job, index) ->
              state = if job.color == "red" then "FAIL" else "PASS"
              if filter.test job.name
                response += "[#{index + 1}] #{state} #{job.name}\n"
            response += "use 'deploy <job_index>' for triggering the deployment"
            msg.send response
          catch error
            msg.send error

# ----------------- DEPLOYMENT -----------------
deployUser = ""
deployEnv = "UNKNOWN"
deployBranch = "UNKNOWN"
         
addEnvChoices = (dialog, m) ->
    m.reply 'Sure, which environment should I deploy then? [CN|DE]'
    dialog.addChoice(/CN$|cn$|china$/i, (msg) ->
      deployEnv = msg.match[0]
      addBranchChoices(dialog, msg)
    )
    dialog.addChoice(/DE$|de$|germany$/i, (msg) ->
      msg.reply 'Sorry, I cannot do that yet... Contact @BartoszBoron for help ;-)'
    )

addBranchChoices = (dialog, m) ->
    m.reply 'Perfect! Which branch should I use?'
    dialog.addChoice(/master$|branch_(.*)/i, (msg) ->
      deployBranch = msg.match[0]
      msg.match[1] = 'p_' + deployEnv + '_FLUS_FLUB_Build_Push'
      msg.match[3] = 'branch=' + deployBranch
      #msg.reply 'Okidoki! Deploying SALLY from branch <' +deployBranch+ '> to <' +deployEnv+ '> environment!'
      jenkinsBuild(msg, false)
    )
    dialog.addChoice(/(.*)/i, (msg) ->
      msg.reply 'Does not seem to be a valid branch! I am confused now... You have to start again...'
    )
# ------------------------------------------------

module.exports = (robot) ->
    
  deployTask = new Conversation(robot)
    
  robot.respond /j(?:enkins)? build ([\w\.\-_ ]+)(, (.+))?/i, (msg) ->
    jenkinsBuild(msg, false)

  robot.respond /j(?:enkins)? b (\d+)/i, (msg) ->
    jenkinsBuildById(msg)

  robot.respond /j(?:enkins)? list( (.+))?/i, (msg) ->
    jenkinsList(msg)

  robot.respond /j(?:enkins)? describe (.*)/i, (msg) ->
    jenkinsDescribe(msg)

  robot.respond /j(?:enkins)? last (.*)/i, (msg) ->
    jenkinsLast(msg)
  
    
  robot.respond /deploy$/, (msg) ->
    dialog = deployTask.startDialog(msg)
    addEnvChoices(dialog, msg)
    dialog.addChoice /(.*)/i, (msg2) ->
      msg2.reply 'It is not a valid choice! Please start again '
      dialog.resetChoices()

  robot.respond /deploy (master|branch_(.*)) to (CN|DE)/i, (msg) ->
    console.log(msg.match)
    jobList = []
    # filter of available jobs for deployment
    branch = msg.match[1]
    env = msg.match[3]
    msg.match[1] = 'p_' + env + '_FLUS_FLUB_Build_Push'
    msg.match[3] = 'branch=' + branch
    jenkinsBuild(msg, false)
  
  robot.respond /deploy (\d+)/i, (msg) ->
    jenkinsBuildById(msg)

  robot.jenkins = {
    list: jenkinsList,
    build: jenkinsBuild
    describe: jenkinsDescribe
    last: jenkinsLast
  }