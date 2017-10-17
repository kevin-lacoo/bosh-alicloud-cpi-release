#!/usr/bin/env bash

set -e

: ${ALICLOUD_ACCESS_KEY_ID:?}
: ${ALICLOUD_SECRET_ACCESS_KEY:?}
: ${ALICLOUD_DEFAULT_REGION:?}
: ${DESTROY_ENVIRONMENT:?}
: ${GIT_USER_EMAIL:?}
: ${GIT_USER_NAME:?}

CURRENT_PATH=$(pwd)
SOURCE_PATH=$CURRENT_PATH/bosh-cpi-src
TERRAFORM_PATH=$CURRENT_PATH/terraform
TERRAFORM_MODULE=$SOURCE_PATH/ci/assets/terraform
TERRAFORM_METADATA=$CURRENT_PATH/terraform-metadata
METADATA=metadata
TERRAFORM_VERSION=0.10.0
TERRAFORM_PROVIDER_VERSION=1.2.4

wget -N https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip
wget -N https://github.com/alibaba/terraform-provider/releases/download/V${TERRAFORM_PROVIDER_VERSION}/terraform-provider-alicloud_linux-amd64.tgz

mkdir -p ${TERRAFORM_PATH}

unzip -o terraform_${TERRAFORM_VERSION}_linux_amd64.zip -d ${TERRAFORM_PATH}
tar -xzvf terraform-provider-alicloud_linux-amd64.tgz
mv -f bin/terraform* ${TERRAFORM_PATH}
rm -rf ./bin
export PATH="${TERRAFORM_PATH}:$PATH"

cd ${TERRAFORM_MODULE}

rm -rf ${METADATA}
touch ${METADATA}

echo "Build terraform environment......"

terraform init && terraform apply -var alicloud_access_key=${ALICLOUD_ACCESS_KEY_ID} -var alicloud_secret_key=${ALICLOUD_SECRET_ACCESS_KEY} -var alicloud_region=${ALICLOUD_DEFAULT_REGION}

echo "Build terraform environment successfully."

function copyToOutput(){

    cp -rf $1/. $2

    cd $2
    ls -la

    git config --global user.email ${GIT_USER_EMAIL}
    git config --global user.name ${GIT_USER_NAME}
    git config --local -l

    git status

    git status | sed -n '$p' | while read LINE
    do
        echo $LINE
        if [[ $LINE != nothing* ]];
        then
            git add .
            git commit -m 'commit metadata'
        fi
    done
    return 0
}

if [ ! -e "./terraform.tfstate" ];
then
    echo "./terraform.tfstate is not exist and then quit."
    exit 0
fi

terraform state list > all_state
echo "Write metadata ......"
cat all_state | while read LINE
do
    if [ $LINE == "alicloud_vswitch.default" ];
    then
        terraform state show $LINE >> $METADATA
        cat $METADATA | while read line
        do
          echo $line
          if [[ $line == id* ]];
          then
              echo vswitch_$line >> $METADATA
          fi
        done
        sed -i '/^id/d' $METADATA
    fi
    if [ $LINE == "alicloud_security_group.sg" ];
    then
        terraform state show $LINE >> $METADATA
        cat $METADATA | while read line
        do
          echo $line
          if [[ $line == id* ]];
          then
              echo security_group_$line >> $METADATA
          fi
        done
        sed -i '/^id/d' $METADATA
    fi
done
echo "Write metadata successfully"

rm -rf ./all_state

sed -i 's/=/:/g' $METADATA

echo "Copy to output ......"
copyToOutput ${SOURCE_PATH} ${TERRAFORM_METADATA}
