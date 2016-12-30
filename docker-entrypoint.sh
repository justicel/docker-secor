#!/bin/bash
set -e
if [ ! -z "$DEBUG" ]; then
	set -x
fi

if [ -z "$ZOOKEEPER_QUORUM" ]; then
	echo "ZOOKEEPER_QUORUM variable not set, launch with -e ZOOKEEPER_QUORUM=zookeeper:2181"
    exit 1
fi
if [[ -z "$AWS_ACCESS_KEY" || -z "$AWS_SECRET_KEY" || -z "$SECOR_S3_BUCKET"  ]]; then
	echo "Missing one or more S3 variables check AWS_ACCESS_KEY, AWS_SECRET_KEY, SECOR_S3_BUCKET"
    exit 1
fi

# validate s3 access
AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY AWS_SECRET_ACCESS_KEY=$AWS_SECRET_KEY aws s3 ls s3://$SECOR_S3_BUCKET > /dev/null


COMMON_CONF=/opt/secor/src/main/config/secor.common.properties
PROD_CONF=/opt/secor/src/main/config/secor.prod.properties
# common conf
sed -i -e "s^aws.access.key=.*$^aws.access.key=${AWS_ACCESS_KEY}^" $COMMON_CONF
sed -i -e "s^aws.secret.key=.*$^aws.secret.key=${AWS_SECRET_KEY}^" $COMMON_CONF
sed -i -e "s^aws.region=.*$^aws.region=${AWS_REGION}^" $COMMON_CONF
sed -i -e "s^monitoring.prefix=.*$^monitoring.prefix=${STATSD_PREFIX}^" $COMMON_CONF
sed -i -e "s^statsd.hostport=.*$^statsd.hostport=${STATSD_HOSTPORT}^" $COMMON_CONF

sed -i -e "s/kafka.seed.broker.port=.*$/kafka.seed.broker.port=${KAFKA_SEED_BROKER_PORT}/" $COMMON_CONF
sed -i -e "s/secor.compression.codec=.*$/secor.compression.codec=org.apache.hadoop.io.compress.GzipCodec/" $COMMON_CONF
sed -i -e "s/secor.file.extension=.*$/secor.file.extension=${SECOR_FILE_EXTENSION:-.seq}/" $COMMON_CONF
sed -i -e "s/kafka.zookeeper.path=\(.*\)$/kafka.zookeeper.path=\1${KAFKA_ZOOKEEPER_PATH}/" $COMMON_CONF
sed -i -e "s/secor.zookeeper.path=\(.*\)$/secor.zookeeper.path=\1${KAFKA_ZOOKEEPER_PATH}/" $COMMON_CONF

# prod conf
sed -i -e "s/kafka.seed.broker.host=.*$/kafka.seed.broker.host=${KAFKA_SEED_BROKER_HOST}/" $PROD_CONF
sed -i -e "s/zookeeper.quorum=.*$/zookeeper.quorum=${ZOOKEEPER_QUORUM}/" $PROD_CONF
sed -i -e "s/secor.s3.bucket=.*$/secor.s3.bucket=${SECOR_S3_BUCKET}/" $PROD_CONF
sed -i -e "s/secor.max.file.size.bytes=.*$/secor.max.file.size.bytes=${SECOR_MAX_FILE_BYTES:-200000000}/" $PROD_CONF
sed -i -e "s/secor.max.file.age.seconds=.*$/secor.max.file.age.seconds=${SECOR_MAX_FILE_SECONDS:-3600}/" $PROD_CONF


KAFKA_TOPIC_FILTER=${SECOR_KAFKA_TOPIC_FILTER:-'.*'}
TIMESTAMP_NAME=${SECOR_TIMESTAMP_NAME:-timestamp}
TIMESTAMP_PATTERN=${SECOR_TIMESTAMP_PATTERN:-timestamp}
WRITER_FACTORY=${SECOR_WRITER_FACTORY:-com.pinterest.secor.io.impl.SequenceFileReaderWriterFactory}

# in COMMON_CONF
sed -i -e "s/secor.kafka.topic_filter=.*$/secor.kafka.topic_filter=${KAFKA_TOPIC_FILTER}/" $COMMON_CONF
sed -i -e "s/message.timestamp.name=.*$/message.timestamp.name=${TIMESTAMP_NAME}/" $COMMON_CONF
sed -i -e "s/message.timestamp.name.separator=.*$/message.timestamp.name.separator=${SECOR_TIMESTAMP_SEPARATOR}/" $COMMON_CONF
sed -i -e "s/message.timestamp.input.pattern=.*$/message.timestamp.input.pattern=${TIMESTAMP_PATTERN}/" $COMMON_CONF
sed -i -e "s/secor.file.reader.writer.factory=.*$/secor.file.reader.writer.factory=${WRITER_FACTORY}/" $COMMON_CONF

SECOR_GROUP=${SECOR_GROUP:-secor_backup}
SECOR_PARSER=${SECOR_MESSAGE_PARSER:-com.pinterest.secor.parser.OffsetMessageParser}
SECOR_PER_HOUR=${SECOR_PER_HOUR:-false}
SECOR_OSTRICH_PORT=${SECOR_OSTRICH_PORT:-9999}
JVM_MEMORY=${JVM_MEMORY:-512m}

# target conf
cat <<EOF > /opt/secor/src/main/config/secor.prod.target.properties
# Generated by docker-entrypoint.sh

include=secor.prod.properties

# Per hour feature
partitioner.granularity.hour=$SECOR_PER_HOUR

# Name of the Kafka consumer group.
secor.kafka.group=$SECOR_GROUP

# Parser class that extracts partitions from consumed messages.
secor.message.parser.class=$SECOR_PARSER

# S3 path where sequence files are stored.
secor.s3.path=$SECOR_GROUP

# Local path where sequence files are stored before they are uploaded to s3.
secor.local.path=/tmp/$SECOR_GROUP

# Port of the Ostrich server.
ostrich.port=$SECOR_OSTRICH_PORT

EOF
cd /opt/secor/jars
java -ea -Dsecor_group=$SECOR_GROUP -Dlog4j.configuration=file:../log4j.docker.properties -Dconfig=../src/main/config/secor.prod.target.properties \
-cp secor-0.22-SNAPSHOT.jar:lib/* com.pinterest.secor.main.ConsumerMain
