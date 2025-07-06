#!/bin/bash

die() {
    local msg="$1"
    local code="${2-1}"
    
    echo "error: $msg" >&2
    exit "$code"
}

create_ecs_cluster() {  
    local name="$1"
    local capacity_providers="$2"
    local container_insights_value="$3"

    if [[ -z "$name" || -z "$capacity_providers" ]]; then
        echo "Usage: $0 <name> <capacity_providers> <container_insights_value>" >&2
        return 1
    fi

    local cmd="aws ecs create-cluster --cluster-name $name --capacity-providers $capacity_providers --output text --query 'cluster.clusterArn'"
    if [[ -n "$container_insights_value" ]]; then
        cmd="$cmd --settings name=containerInsights,value=$container_insights_value"
    fi

    local arn
    arn=$(eval "$cmd") || return "$?"

    echo "$arn"
}

create_ecs_task_definition() {
    local name="$1"
    local json_file_path="$2"
    local region="${3:-us-east-1}"

    if [[ -z "$json_file_path" ]]; then
        echo "Usage: $0 <json_file_path> <region>" >&2
        return 1
    fi

    local arn
    arn=$(aws ecs register-task-definition --region "$region" --family "$name" --cli-input-json "file://$json_file_path" --output text --query 'taskDefinition.taskDefinitionArn') || return "$?"

    echo "$arn"
}

create_sg() {
    local name="$1"
    local desc="$2"
    local vpc_id="$3"

    if [[ -z "$name" ]]; then
        echo "(internal error) 'create_sg' is called with no security group name" >&2
        return 1
    fi

    if [[ -z "$desc" ]]; then
        echo "(internal error) 'create_sg' is called with no security group description" >&2
        return 1
    fi

    if [[ -z "$vpc_id" ]]; then
        echo "(internal error) 'create_sg' is called with no vpc id"
        return 1
    fi

    local id
    id=$(aws ec2 create-security-group \
        --group-name "${name}" \
        --description "${desc}" \
        --vpc-id "${vpc_id}" \
        --query 'GroupId' \
        --output text) || return "$?"

    echo "$id"
}

allow_incoming_traffic_on_port_ipv4_for_sg() {
    local sg_id="$1"
    local protocol="$2"
    local port="$3"
    local cidr="$4"
    local description="$5"

    if [[ -z "$sg_id" ]]; then
        echo "(internal error) 'allow_incoming_traffic_on_port_ipv4_for_sg' is called with sg_id" >&2
        return 1
    fi

    if [[ -z "$protocol" ]]; then
        echo "(internal error) 'allow_incoming_traffic_on_port_ipv4_for_sg' is called with protocol" >&2
        return 1
    fi

    if [[ -z "$port" ]]; then
        echo "(internal error) 'allow_incoming_traffic_on_port_ipv4_for_sg' is called with port" >&2
        return 1
    fi

    if [[ -z "$cidr" ]]; then
        echo "(internal error) 'allow_incoming_traffic_on_port_ipv4_for_sg' is called with cidr" >&2
        return 1
    fi

    if [[ -z "$description" ]]; then
        echo "(internal error) 'allow_incoming_traffic_on_port_ipv4_for_sg' is called with description" >&2
        return 1
    fi

    aws ec2 authorize-security-group-ingress \
        --group-id "$sg_id" \
        --ip-permissions \
        "IpProtocol=$protocol,FromPort=$port,ToPort=$port,IpRanges=[{CidrIp=$cidr,Description='$description'}]" >"/dev/null" || return "$?"
}

allow_incoming_traffic_on_port_ipv6_for_sg() {
    local sg_id="$1"
    local protocol="$2"
    local port="$3"
    local cidr="$4"
    local description="$5"

    if [[ -z "$sg_id" ]]; then
        echo "(internal error) 'allow_incoming_traffic_on_port_ipv6_for_sg' is called with sg_id" >&2
        return 1
    fi

    if [[ -z "$protocol" ]]; then
        echo "(internal error) 'allow_incoming_traffic_on_port_ipv6_for_sg' is called with protocol" >&2
        return 1
    fi

    if [[ -z "$port" ]]; then
        echo "(internal error) 'allow_incoming_traffic_on_port_ipv6_for_sg' is called with port" >&2
        return 1
    fi

    if [[ -z "$cidr" ]]; then
        echo "(internal error) 'allow_incoming_traffic_on_port_ipv6_for_sg' is called with cidr" >&2
        return 1
    fi

    if [[ -z "$description" ]]; then
        echo "(internal error) 'allow_incoming_traffic_on_port_ipv6_for_sg' is called with description" >&2
        return 1
    fi

    aws ec2 authorize-security-group-ingress \
        --group-id "$sg_id" \
        --ip-permissions \
        "IpProtocol=$protocol,FromPort=$port,ToPort=$port,Ipv6Ranges=[{CidrIpv6=$cidr,Description='$description'}]" >"/dev/null" || return "$?"
}

allow_incoming_traffic_on_port_from_another_sg() {
    local sg_id="$1"
    local protocol="$2"
    local port="$3"
    local source_sg="$4"

    if [[ -z "$sg_id" ]]; then
        echo "(internal error) 'allow_incoming_traffic_on_port_from_another_sg' is called with no security group id" >&2
        return 1
    fi

    if [[ -z "$protocol" ]]; then
        echo "(internal error) 'allow_incoming_traffic_on_port_from_another_sg' is called with no protocol" >&2
        return 1
    fi

    if [[ -z "$port" ]]; then
        echo "(internal error) 'allow_incoming_traffic_on_port_from_another_sg' is called with no port" >&2
        return 1
    fi

    if [[ -z "$source_sg" ]]; then
        echo "(internal error) 'allow_incoming_traffic_on_port_from_another_sg' is called with no other security group id" >&2
        return 1
    fi

    aws ec2 authorize-security-group-ingress \
        --group-id "$sg_id" \
        --protocol "$protocol" \
        --port "$port" \
        --source-group "$source_sg" >"/dev/null" || return "$?"
}

allow_http_for_sg() {
    local sg_id="$1"
    if [[ -z "$sg_id" ]]; then
        die "(internal error) 'allow_http_for_sg' is called with no argument"
    fi

    allow_incoming_traffic_on_port_ipv4_for_sg "$sg_id" "tcp" 80 "0.0.0.0/0" "Allow HTTP from all ipv4 addresses" || return "$?"
    allow_incoming_traffic_on_port_ipv6_for_sg "$sg_id" "tcp" 80 "::/0" "Allow HTTP from all ipv6 addresses" || return "$?"
}

create_target_group() {
    local tg_name="$1"
    local forwarding_protocol="$2"
    local traffic_port="$3"
    local vpc_id="$4"
    local target_type="${5:-instance}"
    local health_check_protocol="${6:-HTTP}"
    local health_check_port="${7:-$traffic_port}"
    local health_check_path="${8:-/}"
    local health_check_interval_seconds="${9:-30}"
    local health_check_timeout_seconds="${10:-6}"
    local healthy_threshold_count="${11:-5}"
    local unhealthy_threshold_count="${12:-2}"

    if [[ -z "$tg_name" ]]; then
        echo "(internal error) 'create_target_group' is called with no tg_name" >&2
        return 1
    fi

    if [[ -z "$forwarding_protocol" ]]; then
        echo "(internal error) 'create_target_group' is called with no forwarding_protocol" >&2
        return 1
    fi

    if [[ -z "$traffic_port" ]]; then
        echo "(internal error) 'create_target_group' is called with no traffic_port" >&2
        return 1
    fi

    if [[ -z "$vpc_id" ]]; then
        echo "(internal error) 'create_target_group' is called with no vpc_id" >&2
        return 1
    fi

    if [[ -z "$target_type" ]]; then
        echo "(internal error) 'create_target_group' is called with no target_type" >&2
        return 1
    fi

    if [[ -z "$health_check_protocol" ]]; then
        echo "(internal error) 'create_target_group' is called with no health_check_protocol" >&2
        return 1
    fi

    if [[ -z "$health_check_port" ]]; then
        echo "(internal error) 'create_target_group' is called with no health_check_port" >&2
        return 1
    fi

    if [[ -z "$health_check_path" ]]; then
        echo "(internal error) 'create_target_group' is called with no health_check_path" >&2
        return 1
    fi

    if [[ -z "$health_check_interval_seconds" ]]; then
        echo "(internal error) 'create_target_group' is called with no health_check_interval_seconds" >&2
        return 1
    fi

    if [[ -z "$health_check_timeout_seconds" ]]; then
        echo "(internal error) 'create_target_group' is called with no health_check_timeout_seconds" >&2
        return 1
    fi

    if [[ -z "$healthy_threshold_count" ]]; then
        echo "(internal error) 'create_target_group' is called with no healthy_threshold_count" >&2
        return 1
    fi

    if [[ -z "$unhealthy_threshold_count" ]]; then
        echo "(internal error) 'create_target_group' is called with no unhealthy_threshold_count" >&2
        return 1
    fi

    local tg_arn
    tg_arn=$(aws elbv2 create-target-group \
        --name "$tg_name" \
        --protocol "$forwarding_protocol" \
        --port "$traffic_port" \
        --vpc-id "$vpc_id" \
        --target-type "$target_type" \
        --health-check-protocol "$health_check_protocol" \
        --health-check-port "$health_check_port" \
        --health-check-path "$health_check_path" \
        --health-check-interval-seconds "$health_check_interval_seconds" \
        --health-check-timeout-seconds "$health_check_timeout_seconds" \
        --healthy-threshold-count "$healthy_threshold_count" \
        --unhealthy-threshold-count "$unhealthy_threshold_count" \
        --query 'TargetGroups[0].TargetGroupArn' \
        --output text) || return "$?"

    echo "$tg_arn"
}

create_load_balancer() {
    local name="$1"
    local scheme="$2"
    local type="$3"
    local ip_address_type="$4"
    local security_groups_str="$5"
    local subnets_str="$6"
    
    local security_groups
    read -ra security_groups <<< "$security_groups_str"

    local subnets
    read -ra subnets <<< "$subnets_str"

    if [[ -z "$name" ]]; then
        echo "(internal error) 'create_load_balancer' is called with no name" >&2
        return 1
    fi

    if [[ -z "$scheme" ]]; then
        echo "(internal error) 'create_load_balancer' is called with no scheme" >&2
        return 1
    fi

    if [[ -z "$type" ]]; then
        echo "(internal error) 'create_load_balancer' is called with no type" >&2
        return 1
    fi

    if [[ -z "$ip_address_type" ]]; then
        echo "(internal error) 'create_load_balancer' is called with no ip_address_type" >&2
        return 1
    fi

    if [[ -z "$security_groups_str" ]]; then
        echo "(internal error) 'create_load_balancer' is called with no security_groups" >&2
        return 1
    fi

    if [[ -z "$subnets_str" ]]; then
        echo "(internal error) 'create_load_balancer' is called with no subnets" >&2
        return 1
    fi

    local lb_arn
    lb_arn=$(aws elbv2 create-load-balancer \
        --name "$name" \
        --scheme "$scheme" \
        --type "$type" \
        --ip-address-type "$ip_address_type" \
        --security-groups "${security_groups[@]}" \
        --subnets "${subnets[@]}" \
        --query 'LoadBalancers[0].LoadBalancerArn' \
        --output text) || return "$?"

    echo "$lb_arn"
}

describe_vpc_subnets() {
    local vpc_id="$1"
    if [[ -z "$vpc_id" ]]; then
        echo "(internal error) 'describe_vpc_subnets' is called with no vpc_id" >&2
        return 1
    fi

    aws ec2 describe-subnets --filters "Name=vpc-id,Values=$vpc_id" --query "Subnets[*].SubnetId" --output text
}

create_load_balancer_listener() {
    local lb_arn="$1"
    local protocol="$2"
    local port="$3"
    local target_groupd_arn="$4"
    local action="${5:-forward}"
    local certificate_arn="$6"

    if [[ -z "$lb_arn" ]]; then
        echo "(internal error) 'create_load_balancer_listener' is called with no lb_arn" >&2
        return 1
    fi

    if [[ -z "$protocol" ]]; then
        echo "(internal error) 'create_load_balancer_listener' is called with no protocol" >&2
        return 1
    fi

    if [[ -z "$port" ]]; then
        echo "(internal error) 'create_load_balancer_listener' is called with no port" >&2
        return 1
    fi

    if [[ -z "$target_groupd_arn" ]]; then
        echo "(internal error) 'create_load_balancer_listener' is called with no target_groupd_arn" >&2
        return 1
    fi

    local cmd
    cmd="aws elbv2 create-listener \
            --load-balancer-arn $lb_arn \
            --protocol $protocol \
            --port $port \
            --default-actions Type=$action,TargetGroupArn=$target_groupd_arn \
            --query 'Listeners[0].ListenerArn' \
            --output text"

    if [[ -n "$certificate_arn" ]]; then
        cmd+=" --certificates CertificateArn=$certificate_arn"
    fi

    local listener_arn
    listener_arn=$(eval "$cmd") || return "$?"

    echo "$listener_arn"
}

create_load_balancer_http_listener() {
    local lb_arn="$1"
    local tg_arn="$2"
    if [[ -z "$lb_arn" ]]; then
        echo "(internal error) 'create_load_balancer_http_listener' is called with no lb_arn" >&2
        return 1
    fi

    if [[ -z "$tg_arn" ]]; then
        echo "(internal error) 'create_load_balancer_http_listener' is called with no tg_arn" >&2
        return 1
    fi

    local listener_arn
    listener_arn=$(create_load_balancer_listener "$lb_arn" "HTTP" "80" "$tg_arn") || return "$?"

    echo "$listener_arn"
}

create_ecs_service() {
    local service_name="$1"
    local cluster_name="$2"
    local task_def_name="$3"
    local desired_count="${4}"
    local launch_type="${5}"
    local tasks_subnets="$6"
    local tasks_security_groups="$7"
    local public_ip_enabled_for_tasks="$8"
    local deployment_controller="${9}"
    local load_balancer_configuration="${10}"
    local deployment_configuration="${11}"

    if [[ -z "$service_name" || -z "$cluster_name" || -z "$task_def_name" || -z "$desired_count" || -z "$launch_type" || -z "$tasks_subnets" || -z "$tasks_security_groups" || -z "$public_ip_enabled_for_tasks" || -z "$deployment_controller" || -z "$load_balancer_configuration" ]]; then
        echo "Usage: $0 \
            <service_name> \
            <cluster_name> \
            <task_def_name> \
            <desired_count> \
            <launch_type> \
            <tasks_subnets> \
            <tasks_security_groups> \
            <public_ip_enabled_for_tasks> \
            <deployment_controller> \
            <load_balancer_configuration> \
            <deployment_configuration>" >&2
        return 1
    fi

    local tasks_subnets_arr
    read -ra tasks_subnets_arr <<< "$tasks_subnets"
    local tasks_subnets_quoted_str
    tasks_subnets_quoted_str=$(printf '"%s",' "${tasks_subnets_arr[@]}")
    tasks_subnets_quoted_str=${tasks_subnets_quoted_str%,}
    
    local tasks_security_groups_arr
    read -ra tasks_security_groups_arr <<< "$tasks_security_groups"
    local tasks_security_groups_quoted_str
    tasks_security_groups_quoted_str=$(printf '"%s",' "${tasks_security_groups_arr[@]}")
    tasks_security_groups_quoted_str=${tasks_security_groups_quoted_str%,}
    

    local cmd="
    aws ecs create-service \
        --service-name '$service_name' \
        --cluster '$cluster_name' \
        --task-definition '$task_def_name' \
        --desired-count $desired_count \
        --launch-type '$launch_type' \
        --output text \
        --query 'service.serviceArn' \
        --deployment-controller type=$deployment_controller \
        --network-configuration '{
            \"awsvpcConfiguration\": {
                \"subnets\": [$tasks_subnets_quoted_str],
                \"securityGroups\": [$tasks_security_groups_quoted_str],
                \"assignPublicIp\": \"$public_ip_enabled_for_tasks\"
            }
        }'"

    if [[ -n "$load_balancer_configuration" ]]; then
        cmd+=" --load-balancers '$load_balancer_configuration'"
    fi

    if [[ -n "$deployment_configuration" ]]; then
        cmd+=" --deployment-configuration '$deployment_configuration'"
    fi

    local arn
    arn=$(eval "$cmd") || return "$?"

    echo "$arn"
}

create_scalable_target() {
    local service_namespace="$1"
    local scalable_dimension="$2"
    local resource_id="$3"
    local min_capacity="$4"
    local max_capacity="$5"
    
    if [[ -z "$service_namespace" || -z "$scalable_dimension" || -z "$resource_id" || -z "$min_capacity" || -z "$max_capacity" ]]; then
        echo "Usage: $0 \
            <service_namespace> \
            <scalable_dimension> \
            <resource_id> \
            <min_capacity> \
            <max_capacity>" >&2
        return 1
    fi

    local scalable_target_arn
    scalable_target_arn=$(aws application-autoscaling register-scalable-target \
        --service-namespace "$service_namespace" \
        --scalable-dimension "$scalable_dimension" \
        --resource-id "$resource_id" \
        --min-capacity "$min_capacity" \
        --max-capacity "$max_capacity" \
        --output text \
        --query 'ScalableTargetARN') || return "$?"

    echo "$scalable_target_arn"
}

create_scaling_policy() {
    local policy_name="$1"
    local service_namespace="$2"
    local scalable_dimension="$3"
    local resource_id="$4"
    local policy_type="$5"
    local target_tracking_configuration="$6"

    if [[ -z "$policy_name" || -z "$service_namespace" || -z "$scalable_dimension" || -z "$resource_id" || -z "$policy_type" || -z "$target_tracking_configuration" ]]; then
        echo "Usage: $0 \
            <policy_name> \
            <service_namespace> \
            <scalable_dimension> \
            <resource_id> \
            <policy_type> \
            <target_tracking_configuration>" >&2
        return 1
    fi

    local arn
    arn=$(aws application-autoscaling put-scaling-policy \
        --policy-name "$policy_name" \
        --service-namespace "$service_namespace" \
        --scalable-dimension "$scalable_dimension" \
        --resource-id "$resource_id" \
        --policy-type "$policy_type" \
        --target-tracking-scaling-policy-configuration "$target_tracking_configuration" \
        --query 'PolicyARN' \
        --output text) || return "$?"

    echo "$arn"
}

configure_service_autoscaling() {
    local policy_name="$1"
    local service_namespace="$2"
    local scalable_dimension="$3"
    local resource_id="$4"
    local min_capacity="$5"
    local max_capacity="$6"
    local policy_type="$7"
    local target_tracking_configuration="$8"

    local scalable_target_arn
    scalable_target_arn=$(create_scalable_target "$service_namespace" "$scalable_dimension" "$resource_id" "$min_capacity" "$max_capacity") || return "$?"
    echo "$scalable_target_arn"

    local policy_arn
    policy_arn=$(create_scaling_policy "$policy_name" "$service_namespace" "$scalable_dimension" "$resource_id" "$policy_type" "$target_tracking_configuration") || return "$?"
    echo "$policy_arn"
}

# configs

## general config
vpc_id="vpc-0c39a1bc674978444"
vpc_subnets="$(describe_vpc_subnets "$vpc_id")"

## cluster config
cluster_name="cluster-vproapp"

## task definition config
task_definition_name="taskdef-vproapp"
task_definition_json_file="task_def.json"

## tasks load balancer config
lb_sg_name="secg-lb-vproapp-tasks"
lb_sg_desc="$lb_sg_name"
lb_name="lb-vproapp-tasks"

## target group config
tg_name="tg-vproapp-containers"

## tasks config
tasks_sg_name="secg-tasks-vproapp"
tasks_sg_desc="$tasks_sg_name"

## service config
service_name="service-vproapp"

## autoscaling config
autoscaling_policy_name="policy-autoscaling-vproapp"
scalable_service_namespace="ecs"
scalable_dimension="ecs:service:DesiredCount"
resource_id="service/$cluster_name/$service_name"
min_capacity="1"
max_capacity="4"
scaling_policy_type="TargetTrackingScaling"
target_tracking_configuration="{\"TargetValue\":50,\"PredefinedMetricSpecification\":{\"PredefinedMetricType\":\"ECSServiceAverageCPUUtilization\"}, \"ScaleInCooldown\":60, \"ScaleOutCooldown\":60}"

# create cluster
# shellcheck disable=SC2034
cluster_arn=$(create_ecs_cluster "$cluster_name" "FARGATE" "enabled") || die "Failed to create cluster"

# create task definition
# shellcheck disable=SC2034
task_definition_arn=$(create_ecs_task_definition "$task_definition_name" "$task_definition_json_file") || die "Failed to create task definition"

# create security groups
## load balancer
lb_sg_id=$(create_sg "$lb_sg_name" "$lb_sg_desc" "$vpc_id") || die "Failed to create security group for load balancer"
allow_http_for_sg "$lb_sg_id" || die "Failed to allow http for security group for load balancer"

## tasks
tasks_sg_id=$(create_sg "$tasks_sg_name" "$tasks_sg_desc" "$vpc_id") || die "Failed to create security group for tasks"
allow_incoming_traffic_on_port_from_another_sg "$tasks_sg_id" "tcp" 8080 "$lb_sg_id" || die "Failed to allow incoming traffic on port 8080 from load balancer security group"

# create load balancer
lb_arn=$(create_load_balancer "$lb_name" "internet-facing" "application" "ipv4" "$lb_sg_id" "$vpc_subnets") || die "Failed to create load balancer"

# create target group
tg_arn=$(create_target_group "$tg_name" "HTTP" "8080" "$vpc_id" "ip") || die "Failed to create target group"

# create load balancer listener
listener_arn=$(create_load_balancer_http_listener "$lb_arn" "$tg_arn") || die "Failed to create load balancer listener"

# create ECS service
# shellcheck disable=SC2034
service_arn=$(create_ecs_service \
    "$service_name" \
    "$cluster_name" \
    "$task_definition_name" \
    1 \
    "FARGATE" \
    "$vpc_subnets" \
    "$tasks_sg_id" \
    "ENABLED" \
    "ECS" \
    "[{\"targetGroupArn\":\"$tg_arn\",\"containerName\":\"container-vproapp\",\"containerPort\":8080}]") || die "Failed to create ECS service"

# configure service autoscaling
# shellcheck disable=SC2034
scaling_target_and_policy_arns=$(configure_service_autoscaling \
    "$autoscaling_policy_name" \
    "$scalable_service_namespace" \
    "$scalable_dimension" \
    "$resource_id" \
    "$min_capacity" \
    "$max_capacity" \
    "$scaling_policy_type" \
    "$target_tracking_configuration") || die "Failed to configure service autoscaling"