export NAME := Comparative Analysis
export EC2_KEY := geotrellis-cluster
export AWS_DEFAULT_REGION := us-east-1
export S3_URI := s3://geotrellis-test/ca
export SUBNET_ID := subnet-c5fefdb1

export MASTER_INSTANCE := m3.xlarge
export MASTER_PRICE := 0.5
export WORKER_INSTANCE := m3.2xlarge
export WORKER_PRICE := 0.5
export WORKER_COUNT := 1

export DRIVER_MEMORY := 4200M
export DRIVER_CORES := 2
export EXECUTOR_MEMORY := 4200M
export EXECUTOR_CORES := 2
export YARN_OVERHEAD := 700


GEODOCKER_BOOTSTRAP=s3://geotrellis-test/geodocker/bootstrap-geodocker-accumulo.sh

EMR_IP=$(shell $(warning "Waiting for emr cluster ${1}") \
  aws emr wait cluster-running --cluster-id ${1} 1>&2 \
	&& aws emr describe-cluster --output json  --cluster-id ${1} | jq -r '.Cluster.MasterPublicDnsName')

define EMR_CREATE_CLUSTER
	$(warning "Creating ${1} cluster")
	aws emr create-cluster --name "${NAME} ${1} ${USER}" \
--release-label emr-5.0.0 \
--output text \
--use-default-roles \
--log-uri ${S3_URI}/logs \
--ec2-attributes KeyName=${EC2_KEY},SubnetId=${SUBNET_ID} \
--applications Name=Hadoop Name=Zookeeper Name=Spark \
--instance-groups \
Name=Master,BidPrice=${MASTER_PRICE},InstanceCount=1,InstanceGroupType=MASTER,InstanceType=${MASTER_INSTANCE} \
Name=Workers,BidPrice=${WORKER_PRICE},InstanceCount=${WORKER_COUNT},InstanceGroupType=CORE,InstanceType=${WORKER_INSTANCE} \
--bootstrap-actions Name=bootstrap-${1},Path=${GEODOCKER_BOOTSTRAP},Args=[-i=${2},-n=gis,-p=secret] \
| tee ${1}-cluster-id.txt
endef

GEOWAVE_CLUSTER_ID=$(shell cat geowave-cluster-id.txt)
GEOMESA_CLUSTER_ID=$(shell cat geomesa-cluster-id.txt)

GEOWAVE_ZOOKEEPER=$(call EMR_IP,${GEOWAVE_CLUSTER_ID})
GEOMESA_ZOOKEEPER=$(call EMR_IP,${GEOMESA_CLUSTER_ID})

geomesa-cluster-id.txt:
	$(call EMR_CREATE_CLUSTER,geomesa,quay.io/geodocker/accumulo-geomesa)
	@until [[ -f geomesa-cluster-id.txt ]] ; do :; done # wait to avoid file system race

geowave-cluster-id.txt:
	$(call EMR_CREATE_CLUSTER,geowave,quay.io/geodocker/accumulo-geowave)
	@until [[ -f geomesa-cluster-id.txt ]] ; do :; done # wait to avoid file system race

deploy: geomesa-cluster-id.txt geowave-cluster-id.txt
	terraform apply \
-var 'ec2_key=${EC2_KEY}' \
-var 'subnet_id=${SUBNET_ID}' \
-var 'geomesa_zookeeper=${GEOMESA_ZOOKEEPER}' \
-var 'geowave_zookeeper=${GEOWAVE_ZOOKEEPER}'

destroy-service:
	terraform destroy -force \
-var 'ec2_key=${EC2_KEY}' \
-var 'subnet_id=${SUBNET_ID}' \
-var 'geomesa_zookeeper=NA' \
-var 'geowave_zookeeper=NA'


destroy: destroy-service
	aws emr terminate-clusters --cluster-ids ${GEOMESA_CLUSTER_ID} ${GEOWAVE_CLUSTER_ID}
	@rm -f *-cluster-id.txt

ingest-synthetic: ASSEMBLY_URI=$(shell ./stage-assembly.sh ../synthetic-data mesaPoke ${S3_URI}/jars)
ingest-synthetic:
	./add-steps.sh ${GEOMESA_CLUSTER_ID} "Ingest Synthetic" \
spark-submit --master yarn --deploy-mode cluster \
--driver-memory ${DRIVER_MEMORY} \
--driver-cores ${DRIVER_CORES} \
--executor-memory ${EXECUTOR_MEMORY} \
--executor-cores ${EXECUTOR_CORES} \
--conf spark.dynamicAllocation.enabled=true \
--conf spark.yarn.executor.memoryOverhead=${YARN_OVERHEAD} \
--conf spark.yarn.driver.memoryOverhead=${YARN_OVERHEAD} \
--class com.azavea.geomesa.MesaPoke \
${ASSEMBLY_URI} \
gis ${GEOMESA_ZOOKEEPER} root secret geomesa.test \
point,100,uniform:-180:180,uniform:-90:90,fixed:0,100