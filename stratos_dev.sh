#!/bin/bash
# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.

set -e

# You should not need to change these variables
STRATOS_VERSION="master"
STRATOS_PACK_PATH="/home/vagrant/stratos-packs"
STRATOS_SETUP_PATH="/home/vagrant/stratos-installer"
STRATOS_SOURCE_PATH="/home/vagrant/incubator-stratos"
STRATOS_PATH="/home/vagrant/stratos"
WSO2_CEP_URL="http://people.apache.org/~chsnow"
WSO2_CEP_FILE="wso2cep-3.0.0.zip"
ACTIVEMQ_URL="http://www.mirrorservice.org/sites/ftp.apache.org/activemq/apache-activemq/5.8.0"
ACTIVEMQ_FILE="apache-activemq-5.8.0-bin.tar.gz"
MYSQLJ_URL="http://repo1.maven.org/maven2/mysql/mysql-connector-java/5.1.29"
MYSQLJ_FILE="mysql-connector-java-5.1.29.jar"
HAWTBUF_URL="http://repo1.maven.org/maven2/org/fusesource/hawtbuf/hawtbuf/1.2"
HAWTBUF_FILE="hawtbuf-1.2.jar"
IP_ADDR="192.168.56.5"
PUPPET_IP_ADDR="127.0.0.1"
PUPPET_HOSTNAME="puppet.stratos.com"
MB_IP_ADDR="127.0.0.1"
MB_PORT=61616
CEP_PORT=7611
DOMAINNAME="stratos.com"

if [ "$(arch)" == "x86_64" ]
then
   JAVA_HOME=/usr/lib/jvm/java-7-openjdk-amd64/
else
   JAVA_HOME=/usr/lib/jvm/java-7-openjdk-i386/
fi

progname=$0
progdir=$(dirname $progname)
progdir=$(cd $progdir && pwd -P || echo $progdir)
progarg=''


function finish {
   echo "\n\nReceived SIGINT. Exiting..."
   exit
}

trap finish SIGINT

function main() {
  while getopts 'fcbpnrkdh' flag; do
    progarg=${flag}
    case "${flag}" in
      f) initial_setup ; exit $? ;;
      c) checkout; exit $? ;;
      b) maven_clean_install; exit $? ;;
      p) puppet_setup; exit $? ;;
      n) installer; exit $? ;;
      r) run_stratos; exit $? ;;
      k) kill_stratos; exit $? ;;
      d) development_environment; exit $? ;;
      h) usage ; exit $? ;;
      \?) usage ; exit $? ;;
      *) usage ; exit $? ;;
    esac
  done
  usage
}

function usage () {
   cat <<EOF
Usage: $progname -[f|c|b|p|n|r|k|d|h]
where:
    -f first setup (checkout, build, puppet setup, stratos installer) 
    -c checkout stratos
    -b build stratos
    -p puppet setup
    -n start stratos installer
    -r run stratos in tmux (use CTRL+B then window number to switch tmux windows)
    -k kill stratos tmux session (kills applications runnings in tmux windows)
    -d setup a development environment (installs lubuntu desktop and eclipse)
    -h show this help message

The first option you run must be '-f, first setup'.
All options can be re-run as often as required. 
EOF
   exit 0
}

function downloads () {

  echo -e "\e[32mDownload prerequisite software\e[39m"

  [ -d $STRATOS_PACK_PATH ] || mkdir $STRATOS_PACK_PATH

  if [ ! -e $STRATOS_PACK_PATH/$WSO2_CEP_FILE ]
  then
     wget -q -P $STRATOS_PACK_PATH $WSO2_CEP_URL/$WSO2_CEP_FILE
  fi

  if [ ! -e $STRATOS_PACK_PATH/$MYSQLJ_FILE ]
  then
     wget -q -P $STRATOS_PACK_PATH $MYSQLJ_URL/$MYSQLJ_FILE
  fi

  if [ ! -e $STRATOS_PACK_PATH/$ANDES_CLIENT_JAR_FILE ]
  then
     wget -q -P $STRATOS_PACK_PATH $ANDES_CLIENT_JAR_URL/$ANDES_CLIENT_JAR_FILE
  fi
}

function fix_git_tls_bug() {

  pushd $PWD

  if [ -d ~/git-openssl ]
  then
    # we have already setup git
    return
  fi
  sudo apt-get install -y build-essential fakeroot dpkg-dev
  mkdir ~/git-openssl
  cd ~/git-openssl
  sudo apt-get source -y git
  sudo apt-get build-dep -y git
  sudo apt-get install -y libcurl4-openssl-dev
  sudo dpkg-source -x git_1.7.9.5-1.dsc
  cd git-1.7.9.5
  sudo sed -i 's/libcurl4-gnutls-dev/libcurl4-openssl-dev/g' debian/control
  sudo sed -i '/^TEST =test$/d' debian/rules
  sudo dpkg-buildpackage -rfakeroot -b
  sudo dpkg -i ../git_1.7.9.5-1_i386.deb

  popd
}

function prerequisites() {

  echo -e "\e[32mInstall prerequisite software\e[39m"
  sudo apt-get update
  sudo apt-get install -y --no-install-recommends git maven openjdk-7-jdk 

  if [ "$(arch)" != "x86_64" ]
  then
    fix_git_tls_bug
  fi

  sudo sh -c "
     export DEBIAN_FRONTEND=noninteractive
     echo mysql-server-5.1 mysql-server/root_password password password | debconf-set-selections
     echo mysql-server-5.1 mysql-server/root_password_again password password | debconf-set-selections
     apt-get -y install mysql-server
     "

  if [ "$(arch)" == "x86_64" ]
  then
    grep '^export MAVEN_OPTS' .profile || echo 'export MAVEN_OPTS="-Xmx2048m -XX:MaxPermSize=512m -XX:ReservedCodeCacheSize=256m -Xdebug -Xrunjdwp:transport=dt_socket,address=8888,server=y,suspend=n"' >> .profile
  else
    grep '^export MAVEN_OPTS' .profile || echo 'export MAVEN_OPTS="-Xmx1024m -XX:MaxPermSize=512m -XX:ReservedCodeCacheSize=256m -Xdebug -Xrunjdwp:transport=dt_socket,address=8888,server=y,suspend=n"' >> .profile
  fi
  . .profile
}

function puppet_setup() {

  echo -e "\e[32mSetting up puppet\e[39m"

  pushd $PWD
  cd /home/vagrant

  if [ ! -d puppetinstall ]
  then
    git clone https://github.com/thilinapiy/puppetinstall
    cd puppetinstall
    echo '' | sudo ./puppetinstall -m -d $DOMAINNAME
  fi

  [ -d /etc/puppet/modules/agent/files ] || sudo mkdir -p /etc/puppet/modules/agent/files

  sudo cp -R $STRATOS_SOURCE_PATH/tools/puppet3/manifests/* /etc/puppet/manifests/
  sudo cp -R $STRATOS_SOURCE_PATH/tools/puppet3/modules/* /etc/puppet/modules/
  sudo cp -R $STRATOS_SOURCE_PATH/products/cartridge-agent/modules/distribution/target/apache-stratos-cartridge-agent-*-bin.zip /etc/puppet/modules/agent/files
  sudo cp -R $STRATOS_SOURCE_PATH/products/load-balancer/modules/distribution/target/apache-stratos-load-balancer-*.zip /etc/puppet/modules/agent/files

  sudo sh -c 'echo "*.$DOMAINNAME" > /etc/puppet/autosign.conf'

  # TODO move hardcoded strings to variables
  sudo sed -i -E "s:(\s*[$]local_package_dir.*=).*$:\1 \"/home/vagrant/packs\":g" /etc/puppet/manifests/nodes.pp
  sudo sed -i -E "s:(\s*[$]mb_ip.*=).*$:\1 \"$IP_ADDR\":g" /etc/puppet/manifests/nodes.pp
  sudo sed -i -E "s:(\s*[$]mb_port.*=).*$:\1 \"$MB_PORT\":g" /etc/puppet/manifests/nodes.pp
  sudo sed -i -E "s:(\s*[$]cep_ip.*=).*$:\1 \"$IP_ADDR\":g" /etc/puppet/manifests/nodes.pp
  sudo sed -i -E "s:(\s*[$]cep_port.*=).*$:\1 \"$CEP_PORT\":g" /etc/puppet/manifests/nodes.pp
  # TODO move hardcoded strings to variables
  sudo sed -i -E "s:(\s*[$]truststore_password.*=).*$:\1 \"wso2carbon\":g" /etc/puppet/manifests/nodes.pp

if [ "$(arch)" == "x86_64" ]
then
  JAVA_ARCH="x64"
else
  JAVA_ARCH="i586"
fi

  sudo wget -q -c -P /etc/puppet/modules/java/files \
            --no-cookies --no-check-certificate \
            --header "Cookie: gpw_e24=http%3A%2F%2Fwww.oracle.com%2F; oraclelicense=accept-securebackup-cookie" \
            "http://download.oracle.com/otn-pub/java/jdk/7u51-b13/jdk-7u51-linux-${JAVA_ARCH}.tar.gz"

  sudo sed -i -E "s:(\s*[$]java_name.*=).*$:\1 \"jdk1.7.0_51\":g" /etc/puppet/manifests/nodes.pp
  sudo sed -i -E "s:(\s*[$]java_distribution.*=).*$:\1 \"jdk-7u51-linux-${JAVA_ARCH}.tar.gz\":g" /etc/puppet/manifests/nodes.pp
  popd 
}

function cartridge_setup() {

  echo "TODO: cartridge setup"

}

function installer() {

  echo -e "\e[32mRunning Stratos Installer\e[39m"

  pushd $PWD

  # tmux is useful for starting all the services in different windows
  sudo apt-get install -y tmux

  [ -d $STRATOS_SETUP_PATH ] || mkdir $STRATOS_SETUP_PATH

  cp -rpf $STRATOS_SOURCE_PATH/tools/stratos-installer/* $STRATOS_SETUP_PATH/

  cp -f $STRATOS_SOURCE_PATH/products/stratos/modules/distribution/target/apache-stratos-*.zip $STRATOS_PACK_PATH/
  cp -f $STRATOS_SOURCE_PATH/products/autoscaler/modules/distribution/target/apache-stratos-autoscaler-*.zip $STRATOS_PACK_PATH/
  cp -f $STRATOS_SOURCE_PATH/extensions/cep/stratos-cep-extension/target/org.apache.stratos.cep.extension-*.jar $STRATOS_PACK_PATH

  if [ ! -e $STRATOS_PACK_PATH/$ACTIVEMQ_FILE ]
  then
     wget -q -P $STRATOS_PACK_PATH $ACTIVEMQ_URL/$ACTIVEMQ_FILE
  fi

  # TODO this section is fragile and will break if the version of activemq changes
  [ -e tmp-activemq ] || mkdir tmp-activemq
  tar -C tmp-activemq -xzf $STRATOS_PACK_PATH/$ACTIVEMQ_FILE 
  cp -f tmp-activemq/apache-activemq-5.8.0/lib/activemq-broker-5.8.0.jar $STRATOS_PACK_PATH/
  cp -f tmp-activemq/apache-activemq-5.8.0/lib/activemq-client-5.8.0.jar $STRATOS_PACK_PATH/
  cp -f tmp-activemq/apache-activemq-5.8.0/lib/geronimo-j2ee-management_1.1_spec-1.0.1.jar $STRATOS_PACK_PATH/
  cp -f tmp-activemq/apache-activemq-5.8.0/lib/geronimo-jms_1.1_spec-1.1.1.jar $STRATOS_PACK_PATH/
  rm -rf tmp-activemq

  if [ ! -e $STRATOS_PACK_PATH/$HAWTBUF_FILE ]
  then
     wget -q -P $STRATOS_PACK_PATH $HAWTBUF_URL/$HAWTBUF_FILE
  fi

  sed -i "s:^export setup_path=.*:export setup_path=$STRATOS_SETUP_PATH:g" $STRATOS_SETUP_PATH/conf/stratos-setup.conf
  sed -i "s:^export stratos_pack_path=.*:export stratos_pack_path=$STRATOS_PACK_PATH:g" $STRATOS_SETUP_PATH/conf/stratos-setup.conf
  sed -i "s:^export stratos_path=.*:export stratos_path=$STRATOS_PATH:g" $STRATOS_SETUP_PATH/conf/stratos-setup.conf
  sed -i "s:^export mysql_connector_jar=.*:export mysql_connector_jar=$STRATOS_PACK_PATH/$MYSQLJ_FILE:g" $STRATOS_SETUP_PATH/conf/stratos-setup.conf
  sed -i "s:^export JAVA_HOME=.*:export JAVA_HOME=$JAVA_HOME:g" $STRATOS_SETUP_PATH/conf/stratos-setup.conf
  sed -i "s:^export log_path=.*:export log_path=/home/vagrant/stratos-log:g" $STRATOS_SETUP_PATH/conf/stratos-setup.conf
  sed -i "s:^export host_user=.*:export host_user=vagrant:g" $STRATOS_SETUP_PATH/conf/stratos-setup.conf
  sed -i "s:^export stratos_domain=.*:export stratos_domain=$DOMAINNAME:g" $STRATOS_SETUP_PATH/conf/stratos-setup.conf
  sed -i "s:^export machine_ip=.*:export machine_ip=\"127.0.0.1\":g" $STRATOS_SETUP_PATH/conf/stratos-setup.conf
  sed -i "s:^export offset=.*:export offset=0:g" $STRATOS_SETUP_PATH/conf/stratos-setup.conf
  sed -i "s:^export mb_ip=.*:export mb_ip=$MB_IP_ADDR:g" $STRATOS_SETUP_PATH/conf/stratos-setup.conf
  sed -i "s:^export mb_port=.*:export mb_port=$MB_PORT:g" $STRATOS_SETUP_PATH/conf/stratos-setup.conf
  sed -i "s:^export puppet_ip=.*:export puppet_ip=$PUPPET_IP_ADDR:g" $STRATOS_SETUP_PATH/conf/stratos-setup.conf
  sed -i "s:^export puppet_hostname=.*:export puppet_hostname=$PUPPET_HOSTNAME:g" $STRATOS_SETUP_PATH/conf/stratos-setup.conf
  # set puppet_environment to a dummy value
  sed -i "s:^export puppet_environment=.*:export puppet_environment=XXXXXXXXXXXXXXXXX:g" $STRATOS_SETUP_PATH/conf/stratos-setup.conf
  sed -i "s:^export cep_artifacts_path=.*:export cep_artifacts_path=$STRATOS_SOURCE_PATH/extensions/cep/artifacts/:g" $STRATOS_SETUP_PATH/conf/stratos-setup.conf

  sed -i "s:^export userstore_db_hostname=.*:export userstore_db_hostname=\"localhost\":g" $STRATOS_SETUP_PATH/conf/stratos-setup.conf
  sed -i "s:^export userstore_db_schema=.*:export userstore_db_schema=\"userstore\":g" $STRATOS_SETUP_PATH/conf/stratos-setup.conf
  sed -i "s:^export userstore_db_port=.*:export userstore_db_port=\"3306\":g" $STRATOS_SETUP_PATH/conf/stratos-setup.conf
  sed -i "s:^export userstore_db_user=.*:export userstore_db_user=\"root\":g" $STRATOS_SETUP_PATH/conf/stratos-setup.conf
  sed -i "s:^export userstore_db_pass=.*:export userstore_db_pass=\"password\":g" $STRATOS_SETUP_PATH/conf/stratos-setup.conf

  # pick up the users IaaS settings
  source /home/vagrant/iaas.conf

  # Not apply the changes to stratos-setup.conf for each of the IaaS

  #EC2
  sed -i "s:^export ec2_provider_enabled=.*:export ec2_provider_enabled='$ec2_provider_enabled':g" $STRATOS_SETUP_PATH/conf/stratos-setup.conf
  sed -i "s:^export ec2_identity=.*:export ec2_identity='$ec2_identity':g" $STRATOS_SETUP_PATH/conf/stratos-setup.conf
  sed -i "s:^export ec2_credential=.*:export ec2_credential='$ec2_credential':g" $STRATOS_SETUP_PATH/conf/stratos-setup.conf
  sed -i "s:^export ec2_keypair_name=.*:export ec2_keypair_name='$ec2_keypair_name':g" $STRATOS_SETUP_PATH/conf/stratos-setup.conf
  sed -i "s:^export ec2_owner_id=.*:export ec2_owner_id='$ec2_owner_id':g" $STRATOS_SETUP_PATH/conf/stratos-setup.conf
  sed -i "s:^export ec2_availability_zone=.*:export ec2_availability_zone='$ec2_availability_zone':g" $STRATOS_SETUP_PATH/conf/stratos-setup.conf
  sed -i "s:^export ec2_security_groups=.*:export ec2_security_groups='$ec2_security_groups':g" $STRATOS_SETUP_PATH/conf/stratos-setup.conf

  cd $STRATOS_SETUP_PATH
  chmod +x *.sh

  [ -d $STRATOS_PATH ] || mkdir $STRATOS_PATH
  echo '' | sudo ./stratos-setup.sh -p all

  popd
}

function run_stratos() {

  pushd $PWD

  cd /home/vagrant

  grep '^export JAVA_HOME' ~/.profile || echo "export JAVA_HOME=$JAVA_HOME" >> ~/.profile
  . ~/.profile

  cd /home/vagrant/stratos/apache-stratos-*
  chmod +x bin/*.sh
  ./bin/stratos.sh

  popd
}

function kill_stratos() {
   
   echo -e "\e[32mKill tmux and processes running in tmux windows?\e[39m"
   read -p "[Enter] key to continue, [CTRL+C] to cancel."
   tmux kill-session >/dev/null 2>&1 
}

function development_environment() {

   echo -e "\e[32mSetting up development environment.\e[39m"

   pushd $PWD
   sudo apt-get install -y --no-install-recommends lubuntu-desktop eclipse-jdt xvfb lxde
   sudo apt-get install -y --no-install-recommends vnc4server xrdp

   echo lxsession > ~/.xsession

   cd $STRATOS_SOURCE_PATH
   mvn eclipse:eclipse

   # import projects
   sudo wget -c -P /usr/share/eclipse/dropins/ \
      https://github.com/snowch/test.myapp/raw/master/test.myapp_1.0.0.jar

   # get all the directories that can be imported into eclipse and append them
   # with '-import'

   if [ -e /home/vagrant/workspace ]
   then
      IMPORTS='' # importing fails if workspace already has imported projects 
   else
      IMPORTS=$(find $STRATOS_SOURCE_PATH -type f -name .project)
   fi

   IMPORT_ERRORS=""

   # Although it is possible to import multiple directories with one 
   # invocation of the test.myapp.App, this fails if one of the imports
   # was not successful.  Using a for loop is slower, but more robust
   set +e
   for item in ${IMPORTS[*]};
   do
      IMPORT="$(dirname $item)/"

      # perform the import 
      eclipse -nosplash \
         -application test.myapp.App \
         -data /home/vagrant/workspace \
         -import $IMPORT
      if [ $? != 0 ]
      then
        IMPORT_ERRORS="${IMPORT_ERRORS}\n${IMPORT}"
      fi
   done
   set -e

   if [ -z "$IMPORT_ERRORS" ]
   then
      echo -e "\e[31mImport Errors:\n\n\e[39m"
      echo -e "\e[31m$IMPORT_ERRORS\e[39m"
   fi

   mvn -Declipse.workspace=/home/vagrant/workspace/ eclipse:configure-workspace
   popd
}

function checkout() {

  echo -e "\e[32mChecking out.\e[39m"

  pushd $PWD

  if [ ! -d $STRATOS_SOURCE_PATH ]
  then
     git clone https://git-wip-us.apache.org/repos/asf/incubator-stratos.git $STRATOS_SOURCE_PATH
  else
     cd $STRATOS_SOURCE_PATH
     git checkout master
     git pull
  fi

  cd $STRATOS_SOURCE_PATH
  git checkout ${STRATOS_VERSION}

  popd
}

function maven_clean_install () {
   
   echo -e "\e[32mRunning 'mvn clean install'.\e[39m"
   
   pushd $PWD
   cd /home/vagrant/incubator-stratos
   mvn clean install -DskipTests
   popd
}

function force_clean () {
   
   pushd $PWD
   echo -e "\e[32mIMPORTANT\e[39m"
   echo "Reset your environment?  This will lose any changes you have made."
   echo
   read -p "Please close eclipse, stop any maven jobs and press [Enter] key to continue..."
   
   cd /home/vagrant/incubator-stratos
   mvn clean
   
   rm -rf /home/vagrant/workspace-stratos
   
   rm -rf /home/vagrant/.m2
   
   popd
}

function initial_setup() {
   
   echo -e "\e[32mPerforming initial setup.\e[39m"
   downloads   
   prerequisites
   checkout
   maven_clean_install
   puppet_setup # has a dependency on maven_clean_install
   cartridge_setup
   installer
}

main "$@"
