#!/bin/bash

solrVersion=$1
solrPassword=$2
dnsNameFQDN=$3

{
if [ -f /var/log/solrInstall.log ]; then
    echo "This install script has already run before, log file found, exiting script" > /var/log/Skippedinstall.log
    exit 0
fi
}

# Start logging
exec 3>&1 4>&2
trap 'exec 2>&4 1>&3' 0 1 2 3
exec 1>/var/log/solrInstall.log 2>&1

sed -i "s/SELINUX=enforcing/SELINUX=disabled/" /etc/selinux/config

# Create Disk
if lsblk | grep -q 'sdc'; then
    echo "Use additional disk to store files"
    mkfs.ext4 -F /dev/sdc
    mkdir /opt -p
	diskid=$(blkid | grep -i sdc | cut -d '"' -f2 | cut -d '.' -f1-4)
    mount /dev/sdc /opt
    echo "UUID=$diskid /opt ext4 defaults,nofail 0 0" >> /etc/fstab
	echo "/dev/sdc Disk creation successful"
else
    if lsblk | grep 'sdb1\|/mnt/resource'; then
        echo "Found Temporary Disk"
        echo "Does not Contain additional disk, will create a directory on local drive"
    else
        if lsblk | grep 'sdb'; then
            echo "Use additional disk to store files"
            mkfs.ext4 -F /dev/sdb
            mkdir /opt -p
	        diskid=$(blkid | grep -i sdb | cut -d '"' -f2 | cut -d '.' -f1-4)
            mount /dev/sdb /opt
            echo "UUID=$diskid /opt ext4 defaults,nofail 0 0" >> /etc/fstab
	        echo "/dev/sdb Disk creation successful"
        else
            echo "Does not Contain additional disk, will create a directory on local drive"
        fi
    fi
fi

yum update -y --exclude=WALinuxAgent

# Install Software Packages
# Register the Microsoft RedHat repository
curl https://packages.microsoft.com/config/rhel/7/prod.repo | sudo tee /etc/yum.repos.d/microsoft.repo

packagelist=(
				'wget'
				'unzip'
				'lsof'
				'java-1.8.0-openjdk'
				'java-1.8.0-openjdk-devel'
                'powershell'
			)

for i in "${packagelist[@]}"; do
    if yum -q list installed package "${i}" =~ "${i}"; then
        echo "Package Installed"
    else
        yum install "${i}" -y
    fi
done
 
echo "Check if all packages are installed else try again."
 
for i in "${packagelist[@]}"; do
    if yum -q list installed package "${i}" =~ "${i}"; then
        echo "Package Installed"
    else
        yum install "${i}" -y
    fi
done

java -version

useradd solr

echo $solrPassword | passwd solr --stdin

# Install and configure zookeeper
cd /tmp

wget https://ftp.nluug.nl/internet/apache/zookeeper/zookeeper-3.6.2/apache-zookeeper-3.6.2-bin.tar.gz -q

tar -xvf apache-zookeeper-3.6.2-bin.tar.gz -C /opt
ln -s /opt/apache-zookeeper-3.6.2-bin /opt/zookeeper

cat <<EOT >> /opt/zookeeper/conf/zoo.cfg
tickTime=2000
dataDir=/opt/zookeeper/data
clientPort=2181
initLimit=5
syncLimit=2
server.1=$HOSTNAME:2888:3888
#server.2=<host name 2>:2888:3888
#server.3=<host name 3>:2888:3888

4lw.commands.whitelist=mntr,conf,ruok
EOT

mkdir -p /opt/zookeeper/data
mkdir -p /opt/zookeeper/logs

# Change the ID number for other hosts
echo "1" >/opt/zookeeper/data/myid

cat <<EOT >> /opt/zookeeper/conf/zookeeper-env.sh

ZOO_LOG_DIR=/opt/zookeeper/logs
ZOO_LOG4J_PROP="INFO,ROLLINGFILE"

SERVER_JVMFLAGS="-Xms2048m -Xmx2048m -verbose:gc -XX:+PrintHeapAtGC -XX:+PrintGCDetails -XX:+PrintGCDateStamps -XX:+PrintGCTimeStamps -XX:+PrintTenuringDistribution -XX:+PrintGCApplicationStoppedTime -Xloggc:$ZOO_LOG_DIR/zookeeper_gc.log -XX:+UseGCLogFileRotation -XX:NumberOfGCLogFiles=9 -XX:GCLogFileSize=50M"
EOT

chown -R solr:solr /opt/zookeeper
chown -R solr:solr /opt/apache-zookeeper-3.6.2-bin

cat <<EOT >> /etc/systemd/system/zookeeper.service
[Unit]
Description=Zookeeper Server
After=network.target

[Service]
Type=forking
User=solr
Group=solr
SyslogIdentifier=zookeeper
Restart=always
RestartSec=0s
ExecStart=/opt/zookeeper/bin/zkServer.sh start
ExecStop=/opt/zookeeper/bin/zkServer.sh stop
ExecReload=/opt/zookeeper/bin/zkServer.sh restart

[Install]
WantedBy=multi-user.target
EOT

systemctl daemon-reload
systemctl enable zookeeper
systemctl start zookeeper

# Prepare and INSTALL SOLR
if [ -z "$solrVersion" ]
then
    echo "\$solrVersion is empty, setting to version 8.4.0"
    solrVersion=8.4.0
else
    echo "\$solrVersion is set to $solrVersion"
fi

echo "solrVersion is $solrVersion"


sudo echo 'solr soft nofile 65000' >> /etc/security/limits.conf
sudo echo 'solr hard nofile 65000' >> /etc/security/limits.conf
sudo echo 'root soft nofile 65000' >> /etc/security/limits.conf
sudo echo 'root hard nofile 65000' >> /etc/security/limits.conf
sudo echo 'solr soft nproc  65000' >> /etc/security/limits.conf
sudo echo 'solr hard nproc  65000' >> /etc/security/limits.conf
sudo echo 'root soft nproc  65000' >> /etc/security/limits.conf
sudo echo 'root hard nproc  65000' >> /etc/security/limits.conf

sudo echo 'solr soft nproc 65000' >> /etc/security/limits.d/20-nproc.conf

mkdir -p /opt/dist/
mkdir -p /opt/solr/

mkdir ~/tmp
cd ~/tmp

wget http://archive.apache.org/dist//lucene/solr/${solrVersion}/solr-${solrVersion}.tgz -q

tar zxf solr-${solrVersion}.tgz  solr-${solrVersion}/bin/install_solr_service.sh --strip-components=2
bash ./install_solr_service.sh solr-${solrVersion}.tgz -i /opt/dist -d /opt/solr -u solr -s solr -p 8983

# Configure SOLR memory and leave 2 GB free
cat <<EOT >> /etc/default/set_solr_memory.sh
#!/bin/bash

totalmemory=\$(free -g | gawk  '/Mem:/{print \$2}')
memory=\$((totalmemory-2))g

stringToReplace="SOLR_JAVA_MEM="
stringToReplaceWith="SOLR_JAVA_MEM=\"-Xms512m -Xmx\$memory\""
sed -i "s/.*\$stringToReplace.*/\$stringToReplaceWith/" /etc/default/solr.in.sh 
EOT

# Set ZK_HOST
cat <<EOT >> /etc/default/solr.in.sh
ZK_HOST=$HOSTNAME:2181
# comma rest of the hosts ,<host name 2>:2181,<host name 3>:2181
SOLR_LOG_LEVEL=WARN
# set external FQDN as SOLR Host
SOLR_HOST=$dnsNameFQDN
EOT

# Set SOLR HOME
sed -i "s/#SOLR_HOME=/SOLR_HOME=\/opt\/solr\/data/" /etc/default/solr.in.sh
sed -i "s/#SOLR_PID_DIR=/SOLR_PID_DIR=\/opt\/solr/" /etc/default/solr.in.sh

chmod +x /etc/default/set_solr_memory.sh

# Set Solr Server Service
rm -rf /etc/init.d/solr

cat <<EOT >> /etc/systemd/system/solr.service
[Unit]
Description=Apache SOLR
After=network.target

[Service]
PermissionsStartOnly=true
ExecStartPre=/etc/default/set_solr_memory.sh
Type=forking
User=solr
Group=solr
Environment=SOLR_INCLUDE=/etc/default/solr.in.sh
ExecStart=/opt/dist/solr/bin/solr start
ExecStop=/opt/dist/solr/bin/solr stop
Restart=on-failure
LimitNOFILE=65000
LimitNPROC=65000
TimeoutSec=180s

[Install]
WantedBy=multi-user.target
EOT

chown -R solr:solr /opt/solr/
chown -R solr:solr /opt/dist/
chown -R solr:solr /etc/default/solr.in.sh

systemctl enable solr

