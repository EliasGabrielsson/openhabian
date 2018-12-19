#!/bin/bash

# Log everything to file
exec &> >(tee -a "/boot/first-boot.log")

timestamp() { date +"%F_%T_%Z"; }

fail_inprogress() {
  rm -f /opt/openHABian-install-inprogress
  touch /opt/openHABian-install-failed
  echo -e "$(timestamp) [openHABian] Initial setup exiting with an error!\\n\\n"
  exit 1
}

echo "$(timestamp) [openHABian] Starting the openHABian initial setup."
rm -f /opt/openHABian-install-failed
touch /opt/openHABian-install-inprogress

echo -n "$(timestamp) [openHABian] Storing configuration... "
cp /boot/openhabian.conf /etc/openhabian.conf
sed -i 's/\r$//' /etc/openhabian.conf
# shellcheck source=openhabian.pine64.conf
source /etc/openhabian.conf
echo "OK"

echo -n "$(timestamp) [openHABian] Starting webserver with installation log... "
sh /boot/webif.sh start
sleep 5
webifisrunning=$(ps -ef | pgrep python3)
if [ -z $webifisrunning ]; then
  echo "FAILED"
else
  echo "OK"
fi

userdef="openhabian"
if is_pi; then
  userdef="pi"
fi

echo -n "$(timestamp) [openHABian] Changing default username and password... "
if [ -z ${username+x} ] || ! id $userdef &>/dev/null || id "$username" &>/dev/null; then
  echo "SKIPPED"
else
  usermod -l "$username" $userdef
  usermod -m -d "/home/$username" "$username"
  groupmod -n "$username" $userdef
  chpasswd <<< "$username:$userpw"
  echo "OK"
fi

# While setup: show log to logged in user, will be overwritten by openhabian-setup.sh
echo "watch cat /boot/first-boot.log" > "/home/$username/.bash_profile"

if [ -z "${wifi_ssid}" ]; then
  echo "$(timestamp) [openHABian] Setting up Ethernet connection... OK"
elif grep -q "openHABian" /etc/wpa_supplicant/wpa_supplicant.conf; then
  echo -n "$(timestamp) [openHABian] Setting up Wi-Fi connection... "
  if iwlist wlan0 scanning 2>&1 | grep -q "Interface doesn't support scanning"; then
    # wifi might be blocked
    rfkill unblock wifi
    ifconfig wlan0 up
    if iwlist wlan0 scanning 2>&1 | grep -q "Interface doesn't support scanning"; then
      echo "FAILED" 
      echo -n "$(timestamp) [openHABian] I was not able to turn on the wifi \n Here is some more information: \n"
      rfkill list all
      ifconfig
      fail_inprogress
    fi
  fi
  echo "OK"
else
  echo -n "$(timestamp) [openHABian] Setting up Wi-Fi connection... "

  # check the user input for the country code
  # check: from the start of line, the uppercased input must be followed by a whitespace
  if [ -z "$wifi_country" ]; then
    wifi_country="US"
  elif grep -q "^${wifi_country^^}\s" /usr/share/zoneinfo/zone.tab; then
    wifi_country=${wifi_country^^}
  else
    echo "${wifi_country} is not a valid country code found in /usr/share/zoneinfo/zone.tab"
    echo "Defaulting to US"
    wifi_country="US"
  fi

  echo -e "# config generated by openHABian first boot setup" > /etc/wpa_supplicant/wpa_supplicant.conf
  echo -e "country=$wifi_country\\nctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev\\nupdate_config=1" >> /etc/wpa_supplicant/wpa_supplicant.conf
  echo -e "network={\\n\\tssid=\"$wifi_ssid\"\\n\\tpsk=\"$wifi_psk\"\\n\\tkey_mgmt=WPA-PSK\\n}" >> /etc/wpa_supplicant/wpa_supplicant.conf
  
  sed -i "s/REGDOMAIN=.*/REGDOMAIN=${wifi_country}/g" /etc/default/crda

  if is_pi; then
    echo "OK, rebooting... "
    reboot
  else 
    wpa_cli reconfigure &>/dev/null
    echo "OK"
  fi  
fi

echo -n "$(timestamp) [openHABian] Ensuring network connectivity... "
cnt=0
until ping -c1 9.9.9.9 &>/dev/null || [ "$(wget -qO- http://www.msftncsi.com/ncsi.txt)" == "Microsoft NCSI" ]; do
  sleep 1
  cnt=$((cnt + 1))
  #echo -n ". "
  if [ $cnt -eq 100 ]; then
    echo "FAILED"
    if grep -q "openHABian" /etc/wpa_supplicant/wpa_supplicant.conf && iwconfig 2>&1 | grep -q "ESSID:off"; then
      echo -n "$(timestamp) [openHABian] I was not able to connect to the configured Wi-Fi. \n Please check your signal quality. Reachable Wi-Fi networks are: \n"
      iwlist wlan0 scanning | grep "ESSID" | sed 's/^\s*ESSID:/\t- /g'
      echo -n "$(timestamp) [openHABian] Please try again with your correct SSID and password. \n The following Wi-Fi configuration was used: \n"
      cat /etc/wpa_supplicant/wpa_supplicant.conf
      rm -f /etc/wpa_supplicant/wpa_supplicant.conf
    else
      echo "$(timestamp) [openHABian] The public internet is not reachable. Please check your network."
    fi
    fail_inprogress
  fi
done
echo "OK"

echo -n "$(timestamp) [openHABian] Waiting for dpkg/apt to get ready... "
until apt update &>/dev/null; do sleep 1; done
sleep 10
echo "OK"

echo -n "$(timestamp) [openHABian] Updating repositories and upgrading installed packages... "
apt update &>/dev/null
apt --yes upgrade &>/dev/null
if [ $? -eq 0 ]; then
  echo "OK";
else
  dpkg --configure -a
  apt update &>/dev/null
  apt --yes upgrade &>/dev/null
  if [ $? -eq 0 ]; then echo "OK"; else echo "FAILED"; fail_inprogress; fi
fi

sh /boot/webif.sh reinsure_running
echo -n "$(timestamp) [openHABian] Installing git package... "
apt update &>/dev/null
/usr/bin/apt -y install git &>/dev/null
if [ $? -eq 0 ]; then echo "OK"; else echo "FAILED"; fail_inprogress; fi

echo -n "$(timestamp) [openHABian] Cloning myself... "
/usr/bin/git clone -b master https://github.com/openhab/openhabian.git /opt/openhabian &>/dev/null
if [ $? -eq 0 ]; then echo "OK"; else echo "FAILED"; fail_inprogress; fi
ln -sfn /opt/openhabian/openhabian-setup.sh /usr/local/bin/openhabian-config

echo "$(timestamp) [openHABian] Executing 'openhabian-setup.sh unattended'... "
if (/bin/bash /opt/openhabian/openhabian-setup.sh unattended); then
#if (/bin/bash /opt/openhabian/openhabian-setup.sh unattended_debug); then
  systemctl start openhab2.service
  rm -f /opt/openHABian-install-inprogress
  touch /opt/openHABian-install-successful
else
  fail_inprogress
fi
echo "$(timestamp) [openHABian] Execution of 'openhabian-setup.sh unattended' completed."

echo -n "$(timestamp) [openHABian] Waiting for openHAB to become ready... "
until wget -S --spider http://localhost:8080 2>&1 | grep -q 'HTTP/1.1 200 OK'; do
  sleep 1
done
echo "OK"

echo "$(timestamp) [openHABian] Visit the openHAB dashboard now: http://$hostname:8080"
echo "$(timestamp) [openHABian] To gain access to a console, simply reconnect."
echo "$(timestamp) [openHABian] First time setup successfully finished."
sleep 12
sh /boot/webif.sh inst_done
sleep 12
sh /boot/webif.sh cleanup

# vim: filetype=sh
