#!/bin/bash

# Force LC update when any of these files are changed
echo "${s3_file_tarball_ingester_logrotate}" > /dev/null
echo "${s3_file_tarball_ingester_cloudwatch_sh}" > /dev/null

export AWS_DEFAULT_REGION=$(curl -s http://169.254.169.254/latest/dynamic/instance-identity/document | grep region | cut -d'"' -f4)
export INSTANCE_ID=$(curl http://169.254.169.254/latest/meta-data/instance-id)

export http_proxy="http://${internet_proxy}:3128"
export HTTP_PROXY="$http_proxy"
export https_proxy="$http_proxy"
export HTTPS_PROXY="$https_proxy"
export no_proxy="${non_proxied_endpoints}"
export NO_PROXY="$no_proxy"

echo "Configure AWS Inspector"
cat > /etc/init.d/awsagent.env << AWSAGENTPROXYCONFIG
export https_proxy=$https_proxy
export http_proxy=$http_proxy
export no_proxy=$no_proxy
AWSAGENTPROXYCONFIG

/etc/init.d/awsagent stop
sleep 5
/etc/init.d/awsagent start

echo "Configuring startup scripts paths"
S3_URI_LOGROTATE="s3://${s3_scripts_bucket}/${s3_file_tarball_ingester_logrotate}"
S3_CLOUDWATCH_SHELL="s3://${s3_scripts_bucket}/${s3_file_tarball_ingester_cloudwatch_sh}"

echo "Configuring startup file paths"
mkdir -p /opt/tarball_ingestion/

echo "Installing startup scripts"
$(which aws) s3 cp "$S3_URI_LOGROTATE"          /etc/logrotate.d/tarball_ingestion
$(which aws) s3 cp "$S3_CLOUDWATCH_SHELL"       /opt/tarball_ingestion/tarball_ingestion_cloudwatch.sh

echo "Allow shutting down"
echo "tarball_ingestion     ALL = NOPASSWD: /sbin/shutdown -h now" >> /etc/sudoers

echo "Creating directories"
mkdir -p /var/log/tarball_ingestion

echo "Creating user tarball_ingestion"
useradd tarball_ingestion -m

echo "Setup cloudwatch logs"
chmod u+x /opt/tarball_ingestion/tarball_ingestion_cloudwatch.sh
/opt/tarball_ingestion/tarball_ingestion_cloudwatch.sh \
    "${cwa_metrics_collection_interval}" "${cwa_namespace}" "${cwa_cpu_metrics_collection_interval}" \
    "${cwa_disk_measurement_metrics_collection_interval}" "${cwa_disk_io_metrics_collection_interval}" \
    "${cwa_mem_metrics_collection_interval}" "${cwa_netstat_metrics_collection_interval}" "${cwa_log_group_name}" \
    "$AWS_DEFAULT_REGION"

echo "${environment_name}" > /opt/tarball_ingestion/environment

# Retrieve certificates
ACM_KEY_PASSWORD=$(uuidgen -r)

acm-cert-retriever \
--acm-cert-arn "${acm_cert_arn}" \
--acm-key-passphrase "$ACM_KEY_PASSWORD" \
--private-key-alias "${private_key_alias}" \
--truststore-aliases "${truststore_aliases}" \
--truststore-certs "${truststore_certs}" >> /var/log/acm-cert-retriever.log 2>&1

echo "Retrieving Tarball Ingester artefact..."
$(which aws) s3 cp s3://${s3_artefact_bucket}/dataworks-tarball-ingester/dataworks-tarball-ingester-${tarball_ingester_release}.zip

echo "Changing permissions and moving files"
chown tarball_ingestion:tarball_ingestion -R  /opt/tarball_ingestion
chown tarball_ingestion:tarball_ingestion -R  /var/log/tarball_ingestion

if [[ "${environment_name}" != "production" ]]; then
    echo "Running script to copy synthetic tarballs..."
    echo "Synthetic tarball script would have run" >> /var/log/tarball_ingestion/tarball_ingestion.out 2>&1
fi

echo "Execute Python script to process data..."
echo "Process data script would have run" >> /var/log/tarball_ingestion/tarball_ingestion.out 2>&1