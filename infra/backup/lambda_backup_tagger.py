import boto3

ec2 = boto3.client('ec2')
rds = boto3.client('rds')

def lambda_handler(event, context):

    # Tag EC2 instances
    ec2_instances = ec2.describe_instances()

    for reservation in ec2_instances["Reservations"]:
        for instance in reservation["Instances"]:
            instance_id = instance["InstanceId"]

            ec2.create_tags(
                Resources=[instance_id],
                Tags=[
                    {"Key": "Backup", "Value": "true"}
                ]
            )

    # Tag RDS databases
    db_instances = rds.describe_db_instances()

    for db in db_instances["DBInstances"]:
        db_arn = db["DBInstanceArn"]

        rds.add_tags_to_resource(
            ResourceName=db_arn,
            Tags=[
                {"Key": "Backup", "Value": "true"}
            ]
        )

    return {
        "statusCode": 200,
        "message": "Tagging completed"
    }
