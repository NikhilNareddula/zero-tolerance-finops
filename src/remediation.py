import boto3
import logging
import os

# Set up logging for AWS CloudWatch
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
ec2 = boto3.client('ec2')
sns = boto3.client('sns')

# We will pass the SNS Topic ARN from Terraform as an environment variable later
SNS_TOPIC_ARN = os.environ.get('SNS_TOPIC_ARN')
TARGET_TAG = 'CostCenter'

def lambda_handler(event, context):
    """Main routing function based on the trigger type."""
    
    # Check if this is the 8:00 AM Cron Job
    if event.get('detail-type') == 'Scheduled Event':
        logger.info("Triggered by Cron: Starting Account Audit...")
        run_auditor()
    else:
        # Otherwise, it's a new instance launch
        logger.info("Triggered by EC2 Event: Starting Bouncer check...")
        run_bouncer(event)

def run_bouncer(event):
    """The Bouncer: Inspects a single new instance."""
    try:
        instance_id = event['detail']['instance-id']
    except KeyError:
        logger.error("Could not find instance ID in the event.")
        return
        
    response = ec2.describe_instances(InstanceIds=[instance_id])
    instance_data = response['Reservations'][0]['Instances'][0]
    tags = {tag['Key']: tag['Value'] for tag in instance_data.get('Tags', [])}
    
    if TARGET_TAG not in tags:
        logger.warning(f"VIOLATION: New instance {instance_id} is missing '{TARGET_TAG}' tag. Stopping.")
        
        # 1. Stop it
        ec2.stop_instances(InstanceIds=[instance_id])
        
        # 2. Tag it
        ec2.create_tags(
            Resources=[instance_id],
            Tags=[{'Key': 'SecurityStatus', 'Value': 'Quarantined-Missing-Tag'}]
        )
        
        # 3. Notify the team
        message = f"URGENT: New EC2 instance {instance_id} was launched without a {TARGET_TAG} tag. It has been automatically stopped and quarantined."
        sns.publish(TopicArn=SNS_TOPIC_ARN, Subject="Zero Tolerance: Instance Stopped", Message=message)
        
def run_auditor():
    """The Auditor: Scans all running instances."""
    # Only look for instances that are currently "running"
    response = ec2.describe_instances(
        Filters=[{'Name': 'instance-state-name', 'Values': ['running']}]
    )
    
    violators = []
    
    for reservation in response['Reservations']:
        for instance in reservation['Instances']:
            instance_id = instance['InstanceId']
            tags = {tag['Key']: tag['Value'] for tag in instance.get('Tags', [])}
            
            if TARGET_TAG not in tags:
                violators.append(instance_id)
                
    if violators:
        logger.warning(f"Audit complete. Found {len(violators)} running instances missing tags.")
        message = f"DAILY AUDIT REPORT:\n\nThe following running instances are missing the {TARGET_TAG} tag and are costing the company money:\n\n"
        message += "\n".join(violators)
        message += "\n\nPlease add the required tags today, or they will be scheduled for termination."
        
        sns.publish(TopicArn=SNS_TOPIC_ARN, Subject="Daily Cloud Waste Audit", Message=message)
    else:
        logger.info("Audit complete. All running instances are compliant.")
