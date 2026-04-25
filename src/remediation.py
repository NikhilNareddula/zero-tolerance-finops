import boto3
import logging
import os
import json
from botocore.exceptions import ClientError

# Configure logging for CloudWatch (JSON format)
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Custom JSON formatter for structured logs
class JsonFormatter(logging.Formatter):
    def format(self, record):
        log_entry = {
            'timestamp': self.formatTime(record),
            'level': record.levelname,
            'message': record.getMessage(),
            'instance_id': getattr(record, 'instance_id', None),
            'action': getattr(record, 'action', None)
        }
        return json.dumps(log_entry)

handler = logging.StreamHandler()
handler.setFormatter(JsonFormatter())
logger.addHandler(handler)
logger.propagate = False  # Prevent duplicate logs

ec2 = boto3.client('ec2')
sns = boto3.client('sns')

SNS_TOPIC_ARN = os.environ.get('SNS_TOPIC_ARN')

def publish_notification(subject, message, instance_id=None):
    if not SNS_TOPIC_ARN:
        logger.error("SNS_TOPIC_ARN environment variable is not set", extra={'instance_id': instance_id, 'action': 'SNS_MISSING'})
        return

    try:
        sns.publish(TopicArn=SNS_TOPIC_ARN, Subject=subject, Message=message)
    except ClientError as e:
        logger.error(f"Failed to send SNS notification: {str(e)}", extra={'instance_id': instance_id, 'action': 'SNS_ERROR'})

# --- THE FINOPS RULESET ---
REQUIRED_TAGS = ['env', 'CostCenter']

# Environment-specific instance type rules
INSTANCE_TYPE_RULES = {
    'dev': ['t2.micro', 't3.micro', 't2.small', 't3.small'],
    'test': ['t2.micro', 't3.micro', 't2.small', 't3.small'],
    'stage': ['t2.small', 't3.small', 't2.medium', 't3.medium', 't2.large', 't3.large', 'c5.large', 'c5.xlarge'],
    'uat': ['t2.medium', 't3.medium', 't2.large', 't3.large', 'c5.large', 'c5.xlarge'],
    'prod': []  # No restrictions for production
}

# Instance hourly costs (USD) for savings calculation - Consider moving to config for accuracy
INSTANCE_COSTS = {
    't2.micro': 0.0116, 't3.micro': 0.0104,
    't2.small': 0.023, 't3.small': 0.0208,
    't2.medium': 0.0464, 't3.medium': 0.0416,
    't2.large': 0.0928, 't3.large': 0.0832,
    't2.xlarge': 0.1856, 't3.xlarge': 0.1664,
    't2.2xlarge': 0.3712, 't3.2xlarge': 0.3328,
    'c5.large': 0.085, 'c5.xlarge': 0.17,
    'c5.2xlarge': 0.34, 'c5.4xlarge': 0.68,
    'm5.large': 0.096, 'm5.xlarge': 0.192,
    'm5.2xlarge': 0.384, 'm5.4xlarge': 0.768
}

def lambda_handler(event, context):
    """Main routing function."""
    try:
        if event.get('detail-type') == 'Scheduled Event':
            logger.info("CRON TRIGGER: Starting Auditor (Existing Instances)...")
            run_auditor()
        else:
            logger.info("EVENT TRIGGER: Starting Bouncer (New Instance)...")
            run_bouncer(event)
    except Exception as e:
        logger.error(f"Unhandled Lambda error: {str(e)}", extra={'instance_id': None, 'action': 'LAMBDA_ERROR'})
        return {'statusCode': 500, 'body': json.dumps('Execution failed.')}

    return {'statusCode': 200, 'body': json.dumps('Execution complete.')}

def get_monthly_cost(instance_type):
    """Calculate estimated monthly cost for an instance type."""
    hourly_cost = INSTANCE_COSTS.get(instance_type, 0.10)  # Default $0.10/hr if unknown
    return round(hourly_cost * 730, 2)  # 730 hours per month average

def evaluate_instance(instance_id, tags, instance_type, is_new_launch=False):
    """The Brain: Evaluates rules and returns an ACTION and REASON."""
    # Normalize tags to lowercase for case-insensitive matching
    normalized_tags = {k.lower(): v.lower() if isinstance(v, str) else v for k, v in tags.items()}
    
    env = normalized_tags.get('env', '')

    # RULE 1: Prod is VIP
    if env == 'prod':
        return 'IGNORE', 'Production instance'
    
    # RULE 2: Check for approved exception
    if 'finopsexception' in normalized_tags and normalized_tags['finopsexception'] == 'approved':
        return 'IGNORE', 'Approved exception by FinOps team'

    # RULE 3: Environment-specific instance type restrictions
    if env in INSTANCE_TYPE_RULES:
        allowed_types = INSTANCE_TYPE_RULES[env]
        if allowed_types and instance_type not in allowed_types:
            return 'STOP_IMMEDIATE', f"Instance type {instance_type} not allowed for {env} environment (Allowed: {', '.join(allowed_types[:3])}...)"
    elif env != 'prod':
        # Unknown environment, apply dev rules
        if instance_type not in INSTANCE_TYPE_RULES['dev']:
            return 'STOP_IMMEDIATE', f"Unknown environment '{env}' - applying dev restrictions. Type {instance_type} not allowed."

    # RULE 4: Missing Required Tags (check original case for display)
    missing_tags = [t for t in REQUIRED_TAGS if t.lower() not in normalized_tags]
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
    except KeyError as e:
        logger.error(f"Invalid event structure: missing instance-id. Error: {str(e)}", extra={'instance_id': None, 'action': 'BOUNCER_ERROR'})
        return
    
    try:
        response = ec2.describe_instances(InstanceIds=[instance_id])
        if not response['Reservations']:
            logger.error(f"No instance found for ID: {instance_id}", extra={'instance_id': instance_id, 'action': 'BOUNCER_ERROR'})
            return
        instance = response['Reservations'][0]['Instances'][0]
    except ClientError as e:
        logger.error(f"Failed to describe instance {instance_id}: {str(e)}", extra={'instance_id': instance_id, 'action': 'BOUNCER_ERROR'})
        return
    
    tags = {tag['Key']: tag['Value'] for tag in instance.get('Tags', [])}
    instance_type = instance['InstanceType']
    
    action, reason = evaluate_instance(instance_id, tags, instance_type, is_new_launch=True)
    
    if action == 'STOP_IMMEDIATE':
        # Log with instance ID
        logger.warning(f"BOUNCER: Stopping {instance_id}. Reason: {reason}", extra={'instance_id': instance_id, 'action': 'STOP'})
        try:
            ec2.stop_instances(InstanceIds=[instance_id])
            ec2.create_tags(
                Resources=[instance_id],
                Tags=[{'Key': 'SecurityStatus', 'Value': 'Quarantined-Policy-Violation'}]
            )
        except ClientError as e:
            logger.error(f"Failed to stop/tag instance {instance_id}: {str(e)}", extra={'instance_id': instance_id, 'action': 'STOP_ERROR'})
            return
        
        # Enhanced notification with more details
        env = tags.get('env', 'UNTAGGED')
        cost_center = tags.get('CostCenter', 'UNTAGGED')
        monthly_cost = get_monthly_cost(instance_type)
        
        message = f"""URGENT: AWS Instance Policy Violation Detected

=== INSTANCE DETAILS ===
Instance ID: {instance_id}
Instance Type: {instance_type}
Environment: {env}
Cost Center: {cost_center}

=== VIOLATION ===
{reason}

=== ACTION TAKEN ===
Instance automatically stopped to prevent cost waste

=== COST IMPACT ===
Estimated Monthly Cost: ${monthly_cost}
Potential Monthly Savings: ${monthly_cost}

=== NEXT STEPS ===
1. Review the violation reason above
2. Fix the issue (add required tags or use approved instance type)
3. For exceptions, add tag: FinOpsException=Approved (requires approval)
4. Contact FinOps team for questions

=== APPROVED INSTANCE TYPES BY ENVIRONMENT ===
Dev/Test: t2.micro, t3.micro, t2.small, t3.small
Stage: t2.small - t3.large, c5.large, c5.xlarge
UAT: t2.medium - t3.large, c5.large, c5.xlarge
Prod: No restrictions

AWS Console: https://console.aws.amazon.com/ec2/v2/home#Instances:instanceId={instance_id}
"""
        
        publish_notification(
            subject=f"Zero Tolerance: Instance {instance_id} Stopped - {reason[:50]}",
            message=message,
            instance_id=instance_id
        )

def run_auditor():
    """The Auditor: Scans all running instances on a schedule using Paginators and Batching."""
    logger.info("Starting enterprise-scale FinOps audit...")
    
    # 1. Initialize the Paginator to efficiently handle large numbers of instances without hitting memory limits
    paginator = ec2.get_paginator('describe_instances')
    page_iterator = paginator.paginate(
        Filters=[{'Name': 'instance-state-name', 'Values': ['running']}]
    )
    
    warned_instances_log = []
    stopped_instances_log = []
    
    # Lists to batch our API calls outside the loop  
    instances_to_warn = []
    instances_to_stop = []
    
    # 2. Safely evaluate instances in memory 
    for page in page_iterator:
        for reservation in page.get('Reservations', []):
            for instance in reservation.get('Instances', []):
                try:
                    instance_id = instance['InstanceId']
                    tags = {tag['Key']: tag['Value'] for tag in instance.get('Tags', [])}
                    instance_type = instance['InstanceType']
                    
                    action, reason = evaluate_instance(instance_id, tags, instance_type, is_new_launch=False)
                    
                    if action == 'WARN':
                        instances_to_warn.append(instance_id)
                        warned_instances_log.append(f"{instance_id} - {reason}")
                        
                    elif action in ['STOP_IMMEDIATE', 'STOP_PREVIOUS_WARN']:
                        instances_to_stop.append(instance_id)
                        stopped_instances_log.append(f"{instance_id} - {reason}")
                        
                except Exception as e:
                    # If one instance has weird data, log it and keep moving. Don't crash the Lambda.
                    logger.error(f"Failed to evaluate instance {instance.get('InstanceId', 'Unknown')}: {str(e)}")
                    continue 

    # 3. Execute Actions Outside the Loop (Batched)
    
    # Process Warnings (AWS allows max 1000 IDs per create_tags call) 
    # We batch the tagging to minimize API calls and improve performance, especially for large environments.
    if instances_to_warn:
        logger.info(f"Applying warning tags to {len(instances_to_warn)} instances...")
        for i in range(0, len(instances_to_warn), 1000):
            chunk = instances_to_warn[i:i + 1000]
            try:
                ec2.create_tags(
                    Resources=chunk,
                    Tags=[{'Key': 'FinOpsWarning', 'Value': 'Action-Required'}]
                )
            except ClientError as e:
                logger.error(f"Failed to tag warning chunk: {str(e)}")

    # Process Stops (AWS allows max 1000 IDs per stop_instances call)
  
    if instances_to_stop:
        logger.info(f"Stopping {len(instances_to_stop)} non-compliant instances...")
        for i in range(0, len(instances_to_stop), 1000):
            chunk = instances_to_stop[i:i + 1000]
            try:
                ec2.stop_instances(InstanceIds=chunk)
                ec2.create_tags(
                    Resources=chunk,
                    Tags=[{'Key': 'FinOpsStatus', 'Value': 'Terminated-By-Auditor'}]
                )
            except ClientError as e:
                logger.error(f"Failed to stop/tag instances chunk: {str(e)}")

    # 4. Send the Consolidated Email Report
    if warned_instances_log or stopped_instances_log:
        total_stopped = len(stopped_instances_log)
        total_warned = len(warned_instances_log)
        
        message = f"""DAILY FINOPS AUDIT REPORT
{'='*60}

Summary:
- Instances Stopped: {total_stopped}
- Instances Warned: {total_warned}
- Total Actions: {total_stopped + total_warned}

{'='*60}

"""
        if stopped_instances_log:
            message += "STOPPED INSTANCES (Rule Violations):\n"
            message += "-" * 60 + "\n"
            message += "\n".join(stopped_instances_log) + "\n\n"
            message += "These instances have been stopped to prevent cost waste.\n\n"
        
        if warned_instances_log:
            message += "WARNED INSTANCES (Action Required - Will be stopped next run):\n"
            message += "-" * 60 + "\n"
            message += "\n".join(warned_instances_log) + "\n\n"
            message += "Please fix these instances within 24 hours to avoid automatic shutdown.\n\n"
        
        message += f"""{'='*60}

APPROVED INSTANCE TYPES BY ENVIRONMENT:

Dev/Test:
  - t2.micro, t3.micro, t2.small, t3.small

Stage:
  - t2.small, t3.small, t2.medium, t3.medium
  - t2.large, t3.large, c5.large, c5.xlarge

UAT:
  - t2.medium, t3.medium, t2.large, t3.large
  - c5.large, c5.xlarge

Production:
  - No restrictions (all instance types allowed)

TO REQUEST EXCEPTIONS:
1. Add tag: FinOpsException=Approved (requires team approval)
2. Contact FinOps team with business justification

Questions? Contact your FinOps team.
"""

#push the notification with a clear subject line and detailed message            
        publish_notification(
            subject=f"AWS FinOps Daily Audit: {total_stopped} Stopped, {total_warned} Warned",
            message=message
        )
        logger.info("Auditor found violations. Report sent.")
    else:
        logger.info("Auditor complete. 100% Compliance achieved.")