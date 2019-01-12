#!/usr/bin/env bash

java_webupd8_archive() {
  echo -n "$(timestamp) [openHABian] Preparing and Installing Oracle Java 8 Web Upd8 repository... "
  cond_redirect apt -y install dirmngr
  cond_redirect apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys EEA14886
  if [ $? -ne 0 ]; then echo "FAILED (keyserver)"; exit 1; fi
  rm -f /etc/apt/sources.list.d/webupd8team-java.list
  echo "deb http://ppa.launchpad.net/webupd8team/java/ubuntu trusty main" >> /etc/apt/sources.list.d/webupd8team-java.list
  echo "deb-src http://ppa.launchpad.net/webupd8team/java/ubuntu trusty main" >> /etc/apt/sources.list.d/webupd8team-java.list
  echo oracle-java8-installer shared/accepted-oracle-license-v1-1 select true | /usr/bin/debconf-set-selections
  if [ $? -ne 0 ]; then echo "FAILED (debconf)"; exit 1; fi
  cond_redirect apt update
  cond_redirect apt -y install oracle-java8-installer
  if [ $? -ne 0 ]; then echo "FAILED"; exit 1; fi
  cond_redirect apt -y install oracle-java8-set-default
  if [ $? -eq 0 ]; then echo "OK"; else echo "FAILED"; exit 1; fi
}

java_zulu(){
  cond_redirect systemctl stop openhab2.service
  if is_arm; then
    echo -n "$(timestamp) [openHABian] Installing Zulu Embedded OpenJDK... "
    local downloadPath
    local file
    local jdkTempLocation
    local jdkInstallLocation
    local javapath
    jdkTempLocation=/var/tmp/jdk-new
    file="/var/tmp/.zulu.$$"
    
    if is_aarch64; then 
      downloadPath=curl -s https://www.azul.com/downloads/zulu-embedded | grep -Eo "http://[a-zA-Z0-9./?=_-]*zulu8[a-zA-Z0-9./?=_-]*aarch64.tar.gz"
    else
      downloadPath=curl -s https://www.azul.com/downloads/zulu-embedded | grep -Eo "http://[a-zA-Z0-9./?=_-]*zulu8[a-zA-Z0-9./?=_-]*aarch32hf.tar.gz"
    fi
    cond_redirect wget -nv -O $file $downloadPath
    cond_redirect tar -xpzf $file -C ${jdkTempLocation}
    if [ $? -ne 0 ]; then echo "FAILED"; rm -f ${file}; rm exit 1; fi
    rm -rf $file ${jdkInstallLocation:?}/*
    mv ${jdkTempLocation}/* ${jdkInstallLocation}/; rmdir ${jdkTempLocation}

    javaPath=$(echo $downloadPath|sed 's|http://cdn.azul.com/zulu-embedded/bin/||')
    cond_redirect update-alternatives --install /usr/bin/java java $jdkInstallLocation/$javaPath/bin/java 1083000
    cond_redirect update-alternatives --install /usr/bin/javac java $jdkInstallLocation/$javaPath/bin/javac 1083000
    if [ $? -eq 0 ]; then echo "OK"; else echo "FAILED"; exit 1; fi

  else
    echo -n "$(timestamp) [openHABian] Installing Zulu Enterprise OpenJDK... "
    cond_redirect apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 219BD9C9
    if [ $? -ne 0 ]; then echo "FAILED (keyserver)"; exit 1; fi
    if is_ubuntu; then
      echo "deb $arch http://repos.azulsystems.com/ubuntu stable main" > /etc/apt/sources.list.d/zulu-enterprise.list
    else  
      echo "deb $arch http://repos.azulsystems.com/debian stable main" > /etc/apt/sources.list.d/zulu-enterprise.list
    fi
    cond_redirect apt-get update
    cond_redirect apt -y install zulu-8
    if [ $? -eq 0 ]; then echo "OK"; else echo "FAILED"; exit 1; fi
  fi
  cond_redirect systemctl start openhab2.service
}