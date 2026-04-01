import boto3
import logging
import os
import json

logger = logging.getLogger()
logger.setLevel(logging.INFO)

ec2 = boto3.client('ec2')
sns = boto3.client('sns')

SNS_TOPIC_ARN = os.environ.get('SNS_TOPIC_ARN')

# --- THE FINOPS RULESET ---
REQUIRED_TAGS = ['env', 'CostCenter']
ALLOWED_DEV_TYPES = ['t2.micro', 't3.micro', 't2.small', 't3.small']

def lambda_handler(event, context):
    """Main routing function."""
    if event.get('detail-type') == 'Scheduled Event':
        logger.info("CRON TRIGGER: Starting Auditor (Existing Instances)...")
        run_auditor()
    else:
        logger.info("EVENT TRIGGER: Starting Bouncer (New Instance)...")
        run_bouncer(event)
    
    return {'statusCode': 200, 'body': json.dumps('Execution complete.')}

def evaluate_instance(instance_id, tags, instance_type, is_new_launch=False):
    """The Brain: Evaluates rules and returns an ACTION and REASON."""
    env = tags.get('env', '').lower()

    # RULE 1: Prod is VIP
    if env == 'prod':
        return 'IGNORE', 'Production instance'

    # RULE 2: Expensive Dev/Test instances
    if env != 'prod' and instance_type not in ALLOWED_DEV_TYPES:
        return 'STOP_IMMEDIATE', f"Expensive non-prod type ({instance_type})"

    # RULE 3: Missing Required Tags
    missing_tags = [t for t in REQUIRED_TAGS if t not in tags]
    if missing_tags:
        if is_new_launch:
            # New instances get no mercy
            return 'STOP_IMMEDIATE', f"Launched without required tags: {missing_tags}"
        else:
            # Old instances get ONE warning strike
            if 'FinOpsWarning' in tags:
                return 'STOP_PREVIOUS_WARN', f"Ignored warning to add tags: {missing_tags}"
            else:
                return 'WARN', f"Missing tags: {missing_tags}"

    return 'IGNORE', 'Compliant'

def run_bouncer(event):
    """The Bouncer: Inspects a single new instance the second it boots."""
    try:
        instance_id = event['detail']['instance-id']
    except KeyError:
        return
        
    response = ec2.describe_instances(InstanceIds=[instance_id])
    instance = response['Reservations'][0]['Instances'][0]
    
    tags = {tag['Key']: tag['Value'] for tag in instance.get('Tags', [])}
    instance_type = instance['InstanceType']
    
    action, reason = evaluate_instance(instance_id, tags, instance_type, is_new_launch=True)
    
    if action == 'STOP_IMMEDIATE':
        logger.warning(f"BOUNCER: Stopping {instance_id}. Reason: {reason}")
        ec2.stop_instances(InstanceIds=[instance_id])
        ec2.create_tags(
            Resources=[instance_id],
            Tags=[{'Key': 'SecurityStatus', 'Value': 'Quarantined-Policy-Violation'}]
        )
        sns.publish(
            TopicArn=SNS_TOPIC_ARN, 
            Subject="Zero Tolerance: New Instance Stopped", 
            Message=f"URGENT: New instance {instance_id} violated policy.\nReason: {reason}\nAction: Automatically Stopped."
        )

def run_auditor():
    """The Auditor: Scans all running instances on a schedule."""
    response = ec2.describe_instances(Filters=[{'Name': 'instance-state-name', 'Values': ['running']}])
    
    warned_instances = []
    stopped_instances = []
    
    for reservation in response['Reservations']:
        for instance in reservation['Instances']:
            instance_id = instance['InstanceId']
            tags = {tag['Key']: tag['Value'] for tag in instance.get('Tags', [])}
            instance_type = instance['InstanceType']
            
            action, reason = evaluate_instance(instance_id, tags, instance_type, is_new_launch=False)
            
            if action == 'WARN':
                # Strike 1: Tag it with a warning
                ec2.create_tags(Resources=[instance_id], Tags=[{'Key': 'FinOpsWarning', 'Value': 'Action-Required'}])
                warned_instances.append(f"{instance_id} - {reason}")
                
            elif action in ['STOP_IMMEDIATE', 'STOP_PREVIOUS_WARN']:
                # Strike 2 (or expensive dev): Stop it
                ec2.stop_instances(InstanceIds=[instance_id])
                ec2.create_tags(Resources=[instance_id], Tags=[{'Key': 'FinOpsStatus', 'Value': 'Terminated-By-Auditor'}])
                stopped_instances.append(f"{instance_id} - {reason}")
                
    # Send a single consolidated email report if anything happened
    if warned_instances or stopped_instances:
        message = "DAILY FINOPS AUDIT REPORT\n\n"
        if stopped_instances:
            message += "🚨 STOPPED INSTANCES (Rule Violations):\n" + "\n".join(stopped_instances) + "\n\n"
        if warned_instances:
            message += "⚠️ WARNED INSTANCES (Will be stopped next run if not fixed):\n" + "\n".join(warned_instances) + "\n\n"
            
        sns.publish(TopicArn=SNS_TOPIC_ARN, Subject="AWS FinOps Audit Action Report", Message=message)
        logger.info("Auditor found violations. Report sent.")
    else:
        logger.info("Auditor complete. 100% Compliance achieved.")