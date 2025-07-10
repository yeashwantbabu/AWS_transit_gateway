#!/bin/bash
# AWS CloudFormation Deployment Script
# Deploys VPC, Transit Gateway, and EC2 instances (one per VPC)

# Configuration
REGION="us-east-2"  # Ohio region
ENVIRONMENT="test"
KEY_NAME="yeashwant-TG-ohio"

# Stack Names (All 3 stacks)
VPC_STACK="${ENVIRONMENT}-network-vpc"
TGW_STACK="${ENVIRONMENT}-network-tgw"  # Transit Gateway stack
EC2_STACK="${ENVIRONMENT}-app-ec2"

# Template Files
VPC_TEMPLATE="VPC.yaml"
TGW_TEMPLATE="transit-gateway.yaml"
EC2_TEMPLATE="ec2.yaml"

# VPC Configuration
declare -A VPC_CIDRS=(
    ["1"]="10.0.0.0/16"
    ["2"]="12.0.0.0/16"
    ["3"]="13.0.0.0/16"
    ["4"]="14.0.0.0/16"
)

declare -A VPC_SUBNETS=(
    ["1_1"]="10.0.1.0/24"
    ["1_2"]="10.0.2.0/24"
    ["2_1"]="12.0.1.0/24"
    ["2_2"]="12.0.2.0/24"
    ["3_1"]="13.0.1.0/24"
    ["3_2"]="13.0.2.0/24"
    ["4_1"]="14.0.1.0/24"
    ["4_2"]="14.0.2.0/24"
)

# EC2 Configuration
INSTANCE_TYPE="t2.micro"
AMI_ID="ami-00399ec92321828f5"

# Helper Functions
deploy_stack() {
    local stack_name=$1
    local template=$2
    local params=$3
    
    echo "🚀 Deploying $stack_name..."
    aws cloudformation deploy \
        --stack-name "$stack_name" \
        --template-file "$template" \
        --region "$REGION" \
        --parameter-overrides $params \
        --tags "Environment=$ENVIRONMENT" "Owner=yeashwant" \
        --capabilities CAPABILITY_NAMED_IAM
    
    [ $? -ne 0 ] && { echo "❌ Deployment failed"; exit 1; }
    echo "✅ $stack_name deployed successfully"
}

get_stack_output() {
    local stack_name=$1
    local output_key=$2
    aws cloudformation describe-stacks \
        --stack-name "$stack_name" \
        --query "Stacks[0].Outputs[?OutputKey=='$output_key'].OutputValue" \
        --output text
}

get_stack_resource() {
    local stack_name=$1
    local logical_id=$2
    aws cloudformation describe-stack-resources \
        --stack-name "$stack_name" \
        --query "StackResources[?LogicalResourceId=='$logical_id'].PhysicalResourceId" \
        --output text
}

# 1. Deploy VPC Stack
VPC_PARAMS=""
for vpc in 1 2 3 4; do
    VPC_PARAMS+="Vpc${vpc}Cidr=${VPC_CIDRS[$vpc]} "
    VPC_PARAMS+="Vpc${vpc}Subnet1Cidr=${VPC_SUBNETS["${vpc}_1"]} "
    VPC_PARAMS+="Vpc${vpc}Subnet2Cidr=${VPC_SUBNETS["${vpc}_2"]} "
done

deploy_stack "$VPC_STACK" "$VPC_TEMPLATE" "$VPC_PARAMS"

# 2. Get Network Information
declare -A VPC_IDS SUBNET_IDS ROUTE_TABLE_IDS
for vpc in 1 2 3 4; do
    # Get VPC ID
    VPC_IDS[$vpc]=$(get_stack_output "$VPC_STACK" "VPC${vpc}Id")
    
    # Get Subnet IDs
    SUBNET_IDS["${vpc}_1"]=$(get_stack_resource "$VPC_STACK" "VPC${vpc}Subnet1")
    SUBNET_IDS["${vpc}_2"]=$(get_stack_resource "$VPC_STACK" "VPC${vpc}Subnet2")
    
    # Get Route Table ID
    ROUTE_TABLE_IDS[$vpc]=$(get_stack_resource "$VPC_STACK" "VPC${vpc}RouteTable")
    
    echo "VPC${vpc} ID: ${VPC_IDS[$vpc]}"
    echo "VPC${vpc} Subnet1: ${SUBNET_IDS["${vpc}_1"]}"
    echo "VPC${vpc} Subnet2: ${SUBNET_IDS["${vpc}_2"]}"
    echo "VPC${vpc} RouteTable: ${ROUTE_TABLE_IDS[$vpc]}"
done

# 3. Deploy Transit Gateway Stack
TGW_PARAMS=""
for vpc in 1 2 3 4; do
    TGW_PARAMS+="VPC${vpc}Id=${VPC_IDS[$vpc]} "
    TGW_PARAMS+="VPC${vpc}RouteTableId=${ROUTE_TABLE_IDS[$vpc]} "
    TGW_PARAMS+="VPC${vpc}Cidr=${VPC_CIDRS[$vpc]} "
    TGW_PARAMS+="VPC${vpc}SubnetId=${SUBNET_IDS["${vpc}_1"]} "  # Using first subnet for TGW attachment
done

deploy_stack "$TGW_STACK" "$TGW_TEMPLATE" "$TGW_PARAMS"

# 4. Deploy EC2 Instances
EC2_PARAMS="KeyName=$KEY_NAME InstanceType=$INSTANCE_TYPE AMIId=$AMI_ID "
for vpc in 1 2 3 4; do
    EC2_PARAMS+="VPC${vpc}Id=${VPC_IDS[$vpc]} "
    EC2_PARAMS+="VPC${vpc}SubnetId=${SUBNET_IDS["${vpc}_1"]} "  # Using first subnet for EC2
done

deploy_stack "$EC2_STACK" "$EC2_TEMPLATE" "$EC2_PARAMS"

# 5. Output Results
echo -e "\n🏁 Deployment Complete!"
echo "========================"
echo "VPC Stack: $VPC_STACK"
echo "Transit Gateway Stack: $TGW_STACK"  # Added TGW stack to output
echo "EC2 Stack: $EC2_STACK"

echo -e "\n🌐 EC2 Access URLs:"
for vpc in 1 2 3 4; do
    instance_id=$(get_stack_output "$EC2_STACK" "InstanceVPC${vpc}Id")
    public_ip=$(aws ec2 describe-instances \
        --instance-ids "$instance_id" \
        --query 'Reservations[0].Instances[0].PublicIpAddress' \
        --output text)
    echo "VPC${vpc}: http://${public_ip}"
done