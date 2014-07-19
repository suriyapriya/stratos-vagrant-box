#!/bin/bash

# TODO replace hardcoded string with variables

cp /home/vagrant/stratos-source/products/stratos/modules/distribution/target/apache-stratos-4.0.0-SNAPSHOT.zip files/apache-stratos.zip

wget -N -q -P -nc files/ http://archive.apache.org/dist/activemq/5.9.1/apache-activemq-5.9.1-bin.tar.gz

cp -rf /home/vagrant/stratos-source/tools/stratos-installer/ files/

sudo docker build -t=apachestratos/stratos-single-jvm .
#sudo docker push apachestratos/stratos-single-jvm
