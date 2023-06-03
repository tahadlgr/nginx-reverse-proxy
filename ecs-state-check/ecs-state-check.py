import json
from botocore.vendored import requests
import boto3
from pprint import pprint
import os
from typing import Any, Dict, List
from datetime import datetime, timedelta
import urllib3



def lambda_handler(event, context):


    mainAccountId = boto3.client('sts').get_caller_identity().get('Account').strip()
    id = event["account"]
    accountAlias = boto3.client('organizations').describe_account(AccountId=id).get('Account').get('Name')

    print("account alias: %s"%accountAlias)

    if mainAccountId == id :
        ecs = boto3.client('ecs')
    else:
        boto_sts = boto3.client('sts')

        stsresponse = boto_sts.assume_role(
            RoleArn=f"arn:aws:iam::{id}:role/ecs-api-access-cross-account-role",
            RoleSessionName="Newsession"
            )

        newsession_id = stsresponse["Credentials"]["AccessKeyId"]
        newsession_key = stsresponse["Credentials"]["SecretAccessKey"]
        newsession_token = stsresponse["Credentials"]["SessionToken"]

        ecs = boto3.client(
            'ecs',
            region_name='eu-central-1',
            aws_access_key_id=newsession_id,
            aws_secret_access_key=newsession_key,
            aws_session_token=newsession_token
            )

    fields = list()
    
    cluster_name = event["detail"]["clusterArn"].split('/')[1]
    
    # containerLastStatus = event["detail"]["containers"][0]["lastStatus"]
    
    # desiredStatus = event["detail"]["desiredStatus"]
    
    taskLastStatus = event["detail"]["lastStatus"]

    taskArn = event["detail"]["taskArn"]
    
    global stoppingAt
    stoppingAt = event["detail"]["stoppingAt"]
    
    global stoppedReason
    stoppedReason = event["detail"]["stoppedReason"]
    
    global stopCode
    stopCode = event["detail"]["stopCode"]
    
    response = ecs.describe_tasks(
    cluster = cluster_name,
    tasks = list(taskArn.split())
    )["tasks"]

    taskHealthStatus = response[0]["healthStatus"]

    taskDesiredStatus = response[0]["desiredStatus"]

    print("taskArn: %s taskLastStatus: %s taskHealthStatus: %s taskDesiredStatus: %s"%(taskArn,taskLastStatus,taskHealthStatus,taskDesiredStatus))

    global containerExitCode
    containerExitCode = "NotFound"

    global containerReason
    containerReason = "NotFound"

    global taskStartedAt
    taskStartedAt = "NotFound"

    if "exitCode" in response[0]["containers"][0]:
        containerExitCode = response[0]["containers"][0]["exitCode"]
    
    if "reason" in response[0]["containers"][0]:
        containerReason = response[0]["containers"][0]["reason"]
    
    if "startedAt" in response[0]:
        taskStartedAt = response[0]["startedAt"]       

    if taskLastStatus == "STOPPED" and taskHealthStatus == "UNHEALTHY" :
        fields.append(
            {
                "title": "Task Alert for Unstable Clusters",
                #"value": 
                "short": False,
            }
        )
        try:
            send_slack_notification(
                pretext=" In %s cluster last status of task: %s \n Environment info: %s"%(cluster_name,taskLastStatus,accountAlias),
                fields=fields,
                slack_webhook="https://hooks.slack.com/services/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"
            )

        except Exception as e:

            raise e

    elif taskLastStatus == "STOPPED" and taskDesiredStatus != "STOPPED" :

        fields.append(
            {
                "title": "Task Alert for Unstable Clusters",
                #"value": 
                "short": False,
            }
        )
        try:
            send_slack_notification(
                pretext=" In %s cluster last status of task: %s \n Environment info: %s"%(cluster_name,taskLastStatus,accountAlias),
                fields=fields,
                slack_webhook="https://hooks.slack.com/services/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"
            )

        except Exception as e:

            raise e


    return
        

def send_slack_notification(pretext: str, fields: List[Dict[str, Any]], slack_webhook: str):
    data = {
        "attachments": [
            {
                "color": "#960019",
                "pretext": pretext,
                "fields": fields,
                "footer": " This task has stopped at %s \n Stop reason: %s \n Stop code: %s \n Container exit code: %s \n Container exit reason: %s \n Task started at: %s "%(stoppingAt,stoppedReason,stopCode,containerExitCode,containerReason,taskStartedAt),
                "footer_icon": "https://lifemote.com/wp-content/uploads/2020/04/favicon-1.png",
            }
        ]
    }

    #requests.post(slack_webhook, json=data)
    http = urllib3.PoolManager()
    r = http.request('POST',
                        slack_webhook,
                        body = json.dumps(data),
                        headers = {'Content-Type': 'application/json'},
                        retries = False)
    print(r.read())