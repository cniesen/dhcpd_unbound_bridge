#!/bin/sh

# This script works in tandem with the "dhcpd-lease-parser.awk" script to translate the DHCP lease info from the "dhcpd" service into a form that is friendly for the "unbound" service. The aim is to detect new leases issued by "dhcpd" and then update "unbound" so that it can resolve the IP addresses issued by "dhcpd" to the appropriate hostnames.

INPUTFILE="/var/db/dhcpd.leases" # this is the default FreeBSD DHCP leases file
OUTPUTFILE="/usr/local/etc/unbound/dhcp_lease_entries.conf" # location to store the DHCP lease information so that unbound can use it
DOMAIN="." # takes the form ".domain", use "." if not using a domain
TTL="600" #TTL of the DNS records
MAPPINGSFILE="/usr/local/etc/unbound/mappings.db" # an optional file. allows mapping MAC addresses to specific hostnames

# create the following files if they don't already exist:
test -f $OUTPUTFILE || touch $OUTPUTFILE # just in case this is the very first time and the file doesn't exist yet (to avoid the "stat" command below from throwing an error)
test -f $MAPPINGSFILE || touch $MAPPINGSFILE

# get various file metadata properties (helps to detect whether it's time to parse the leases yet)
INPUTFILE_LASTMODIFIED=$(stat -f %m $INPUTFILE) 
OUTPUTFILE_LASTMODIFIED=$(stat -f %m $OUTPUTFILE) 
MAPPINGSFILE_LASTMODIFIED=$(stat -f %m $MAPPINGSFILE)
OUTPUTFILE_SIZE=$(stat -f %z $OUTPUTFILE)

# if something recently changes, regenerate the "unbound" leases file and update "unbound" as needed
if [ $INPUTFILE_LASTMODIFIED -gt $OUTPUTFILE_LASTMODIFIED ] || [ $MAPPINGSFILE_LASTMODIFIED -gt $OUTPUTFILE_LASTMODIFIED ] || [ $OUTPUTFILE_SIZE -eq 0 ]; then 
	# Create TEMPFILE from current dhcpd leases
	TEMPFILE=$(mktemp /tmp/dhtpd_unbound_bridge.XXXXXX)
	./dhcpd-lease-parser.awk -v DOMAIN=$DOMAIN -v TTL=$TTL -v MAPPINGSFILE=$MAPPINGSFILE $INPUTFILE | sort -u > $TEMPFILE
	

	# Find REMOVALS (Lines in OUTPUTFILE that are not in TEMPFILE)
	comm -23 "$OUTPUTFILE" "$TEMPFILE" | while read -r name _ _ _ _; do
		if [ -n "$name" ]; then
			MSG=$(unbound-control local_data_remove "$name" 2>&1)
			if [ -n "$MSG" ]; then
				logger -t dhcp_unbound_bridge -p daemon.info "Remove $name: $MSG"
			fi
		fi
	done

	# Find ADDITIONS (Lines in TEMPFILE that are not in OUTPUTFILE)
	comm -13 "$OUTPUTFILE" "$TEMPFILE" | while read -r raw_record; do
		if [ -n "$raw_record" ]; then
			MSG=$(unbound-control local_data "$raw_record" 2>&1)
			if [ -n "$MSG" ]; then
				logger -t dhcp_unbound_bridge -p daemon.info "Add record ($raw_record): $MSG"
			fi
		fi
	done


	# Update OUTPUTFILE and remove TEMPFILE
	cat "$TEMPFILE" > "$OUTPUTFILE"
	rm -f "$TEMPFILE"
fi
