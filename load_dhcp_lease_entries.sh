#!/bin/sh

# This script works in tandem with the "dhcpd-lease-parser.awk" script to translate the DHCP lease info from the "dhcpd" service into a form that is friendly for "unbound-control local_datas" command.
# The aim is to load the dynamic dhcp addresses after a fresh "unbound" server (re)start so that it can resolve the IP addresses issued by "dhcpd" to the appropriate hostnames.

INPUTFILE="/var/db/dhcpd.leases" # this is the default FreeBSD DHCP leases file
OUTPUTFILE="/usr/local/etc/unbound/dhcp_lease_entries.conf" # location to store the DHCP lease information so that unbound can use it
DOMAIN="." # takes the form ".domain", use "." if not using a domain
TTL="600" #TTL of the DNS records
MAPPINGSFILE="/usr/local/etc/unbound/mappings.db" # an optional file. allows mapping MAC addresses to specific hostnames

# create the following files if they don't already exist:
test -f $OUTPUTFILE || touch $OUTPUTFILE # just in case this is the very first time and the file doesn't exist yet (to avoid the "stat" command below from throwing an error)
test -f $MAPPINGSFILE || touch $MAPPINGSFILE


./dhcpd-lease-parser.awk -v DOMAIN=$DOMAIN -v TTL=$TTL -v MAPPINGSFILE=$MAPPINGSFILE $INPUTFILE | uniq -u > $OUTPUTFILE
unbound-control local_datas < $OUTPUTFILE