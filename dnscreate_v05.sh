#!/usr/bin/env bash

if [[ "$#" -eq 0  ]]; then
  echo "Not enough arguments"
  exit 1
fi

declare -r namedconf="/etc/named.conf"
declare -r zoneconfig="/var/named/data/${1}.zone"

function err()
{
  echo "[$(date +'%d-%m-%YT%H:%M:%S%z')]: $@" >&2
  return 0
}

function write_zone() 
{
  local NAME=${1}
  cat <<- _EOF_
zone "${NAME}" IN 
{
  type master;
  file "data/${NAME}.zone";
};
_EOF_
}

function write_zone_data()
{
  local sigil='$'
  local start_ttl="${sigil}TTL 2D"
  local NAME=${1}
  cat <<- _EOF_
${start_ttl}
@ IN  SOA ns1.${NAME}.  temnovet.gmail.com  (
                                            $(date +'%Y%m%d')01; serial
                                            2H ; refresh
                                            15M ; retry
                                            2W ; expire
                                            2D ; minimum TTL
                                            )
;;; NS ;;;

@ IN  NS  ns1

;;; A ;;;

ns1 IN  A 192.168.0.53

_EOF_
}

#if [[]]; then
#  
#fi

#############################################################################
# A block of changing configurations of iptables.                           #
# Stop firewalld if it exist and install iptables                           #
# Create iptables rules for port 53 (tcp and udp)                           #
# Restart iptables                                                          #
#############################################################################

if [[ "$(systemctl is-active firewalld)" -eq "active"  ]]; then
  systemctl stop firewalld \
          && systemctl mask firewalld \
          && yum install -y iptables-services \
          && systemctl enable iptables \
          && systemctl start iptables
fi

if [[ "$(systemctl is-active iptables)" -ne "active" ]]; then                  
  echo "IPTABLES is not active"
  exit 1
else
  iptables -F \
    && iptables -A INPUT -m state --state NEW -p udp --dport 53 -j ACCEPT \
    && iptables -A INPUT -m state --state NEW -p tcp --dport 53 -j ACCEPT \
    && service iptables save \
    && systemctl restart iptables
  if [[ "$?" -ne 0 ]]; then
    err "Something wrong in iptables add rules and restart"
    exit 1
  fi
fi


#############################################################################
# A block of named.conf configuration                                       #
#############################################################################

yum install bind -y
if [[ "$?" -ne 0 ]]; then
  err "Error install of bind"
  exit 1
fi

if [[ ! -f "${namedconf}"  ]]; then
  err "Something with named.conf"
  exit 1
fi

if [[ ! -w "${namedconf}" ]]; then
  chmod a+w "${namedconf}" && echo "file is writable now"
fi

if [[ ! -w "${namedconf}" ]]; then
  err "file not exist or not writable"
  exit 1
else
  sed -i 's/allow-query     { localhost; }/allow-query     { any; }/' ${namedconf}
  sed -i 's/127.0.0.1/any/' ${namedconf}
  write_zone ${1} >> ${namedconf}
fi

#############################################################################

touch ${zoneconfig}
if [[ "$?" -ne 0 ]]; then
  err "File of zone config was not created"
  exit 1
fi

if [[ ! -w ${zoneconfig}  ]]; then
  err "File of zone config not writable"
  exit 1
else
  write_zone_data ${1} >> ${zoneconfig}
  if [[ "$?" -ne 0 ]]; then
    err "Something wrong with write of file zone "
    exit 1
  fi
fi


systemctl enable named
if [[ "$?" -ne 0 ]]; then
  err "Something wrong with enadle named"
  exit 1
fi

systemctl start named
if [[ "$?" -ne 0 ]]; then
  err "Error of start named"
  exit 1
fi

if [[ "$(systemctl is-active named)" -ne "active"  ]]; then
  err "Named is not active"
  exit 1
fi

echo "DNS-server is created and started"

exit 0

