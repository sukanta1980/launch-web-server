
#!/bin/bash

# Variables
INSTANCE_TYPE="t2.micro"
AMI_ID="ami-0c55b159cbfafe1f0"  
KEY_NAME="key-pair"
REGION="us-west-2"
SECURITY_GROUP="security-group"
SUBNET_ID="subnet-id"
TOMCAT_VERSION="9.0.54"
WAR_FILE_URL="http://path/to/your.war"  # URL of your WAR file
EIP_ALLOCATION_ID="107.2.24.3"  # Replace with your Elastic IP allocation ID

# Launch EC2 instance
INSTANCE_ID=$(aws ec2 run-instances \
    --image-id $AMI_ID \
    --count 1 \
    --instance-type $INSTANCE_TYPE \
    --key-name $KEY_NAME \
    --security-group-ids $SECURITY_GROUP \
    --subnet-id $SUBNET_ID \
    --region $REGION \
    --query "Instances[0].InstanceId" \
    --output text)

echo "Launched EC2 instance with ID: $INSTANCE_ID"

# Wait for the instance to be in running state
aws ec2 wait instance-running --instance-ids $INSTANCE_ID --region $REGION
echo "Instance $INSTANCE_ID is running"

# Get the public IP of the instance
PUBLIC_IP=$(aws ec2 describe-instances \
    --instance-ids $INSTANCE_ID \
    --region $REGION \
    --query "Reservations[0].Instances[0].PublicIpAddress" \
    --output text)

echo "Instance public IP: $PUBLIC_IP"

# Wait for SSH to be available
echo "Waiting for SSH to be available..."
until nc -z -v -w30 $PUBLIC_IP 22
do
  echo "Waiting for SSH..."
  sleep 5
done

# Install Java, download and configure Tomcat
ssh -o "StrictHostKeyChecking no" -i ~/.ssh/$KEY_NAME.pem ec2-user@$PUBLIC_IP << EOF
  sudo yum update -y
  sudo yum install -y java-1.8.0-openjdk

  wget https://downloads.apache.org/tomcat/tomcat-9/v$TOMCAT_VERSION/bin/apache-tomcat-$TOMCAT_VERSION.tar.gz -P /tmp
  sudo tar -xzf /tmp/apache-tomcat-$TOMCAT_VERSION.tar.gz -C /opt/
  sudo ln -s /opt/apache-tomcat-$TOMCAT_VERSION /opt/tomcat

  sudo /opt/tomcat/bin/startup.sh

  # Wait for Tomcat to start
  until nc -z -v -w30 localhost 8080
  do
    echo "Waiting for Tomcat to start..."
    sleep 5
  done

  wget $WAR_FILE_URL -P /opt/tomcat/webapps/
EOF

echo "Tomcat installed and WAR file deployed"

# Allocate and associate Elastic IP
aws ec2 associate-address \
    --instance-id $INSTANCE_ID \
    --allocation-id $EIP_ALLOCATION_ID \
    --region $REGION

echo "Elastic IP $EIP_ALLOCATION_ID associated with instance $INSTANCE_ID"

echo "EC2 instance with Tomcat configured and WAR file deployed successfully"
