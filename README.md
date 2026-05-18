## dhcpd_unbound_bridge
awk script to parse DHCP leases handed out by the ISC DHCP server and parse them into a format readable by unbound. Original written by @davidbarnhart, adapter by @robdejonge to use explicit hostnames, and updated by @cniesen to load and update dns records without restarting unbound.

After unbound is started/restarted via rccl, the load_dhcp_lease_entries.sh script is run to perform the initial load of the addresses of active leases. 

### How to install (suggested):

1. Place the dhcpd-lease-parser.awk script somewhere like /usr/local/sbin and make sure it's executable (chmod 755)
2. Place the load_dhcp_lease_entries.sh script in the same directory as the unbound configuration files (e.g. /usr/local/etc/unbound/) and make sure it's also executable.  Verify the INPUTFILE, OUTPUTFILE, DOMAIN, TTL, and MAPPINGSFILE properties are correctly set in the script.
3. (optional) Enter your mappings into the mappings.db file (which is just a text file) in a `MA:CA:DD:RE:SS myhostname` format (note the space).
4. Ensure that unbound configuration file (e.g. /usr/local/etc/unbound/unbound.conf) has `remote-control: control-enable: yes` and that the unbound-control command works.
5. Update the `/etc/rc.d/unbound` file to run the load_dhcp_lease_entries.sh script after start.
```
#!/bin/ksh
#
# $OpenBSD: unbound,v 1.9 2024/10/09 15:42:56 kn Exp $

daemon="/usr/sbin/unbound"
daemon_flags="-c /var/unbound/etc/unbound.conf"

. /etc/rc.d/rc.subr

rc_pre() {
        local _anchor=$(/usr/sbin/unbound-checkconf -o auto-trust-anchor-file)

        if [[ -n $_anchor && ! -f $_anchor ]]; then
                /usr/sbin/unbound-anchor -v
        fi

        /usr/sbin/unbound-checkconf
}

rc_start() {
        ${rcexec} ${daemon} ${daemon_flags} ${_bg}

        if [ $? -eq 0 ]; then
                /var/dhcpd_unbound_bridge/load_dhcp_lease_entries.sh
        fi
}

rc_cmd $1
```

Note that an alternative to the cron job would be to leverage the ISC DHCP server's ability to execute a command each time a lease is handed out: https://jpmens.net/2011/07/06/execute-a-script-when-isc-dhcp-hands-out-a-new-lease/ 
For OpenBSD however, this is not an option since this feature isn't availiable with the default dhcpd server.


### Background by @davidbarnhart

Having used pfSense for years, I decided to try my hand at rolling my own FreeBSD-based router. I used the dhcpd port from OpenBSD (/usr/ports/net/dhcpd) and chose to go with unbound as my DNS resolver just for simplicity. This is a common configuration within pfSense and OPNsense. Both of those platforms include an option to register the hostname from dhcpd leases within the unbound DNS config. This lets you use hostnames to reference local machines instead of IP addresses. Basic stuff, or at least I thought.

Unfortunately I couldn't find an out-of-the-box method for taking the info from these dhcpd leases and registering the IP address/hostname combinations with unbound. After studying both pfSense and OPNsense, I realized that this functionality is handled by some additional scripts unique to each project. Typically there is a file watcher on the dhcpd lease file, which kicks off some additional parsing scripts each time the file is modified. OPNsense seemed like it was using Python-based scripts, while pfSense seemed to be relying on a much older Perl script. I thought about installing Python on my router but wanted to avoid that if possible.

I found a couple other projects that offered some level of support for parsing dhcp leases and registering them with unbound. However, each required some sort of dependency that I didn't really want. That's when I eventually decided to skip the file watcher (again for simplicity) and handle the parsing with a combination of awk and sh - tools that ship with every FreeBSD system.

The awk script does the majority of the work, trying to parse valid leases (throwing out adandoned or expired leases). The shell script uses this awk script to read in the dhcpd leases file and output a file that is suitable for unbound. At that point, you just need to tell unbound to include the parsed file and reload the unbound config each time the parsed file is updated. I added a cron job to kick this off every five minutes, which seemed about good enough.


### Modification by @robdejonge

Instead of using the `client-hostname` directive from the `dhcpd.leases` file, I needed a way to use explicit hostnames so that whatever each host tells `dhcpd` can be ignored and entries in `unbound` are the way I want them to be. Some devices can't be configured to use a sensible hostname, and the non-sensical ones can be hard to recall! The script will now search `mappings.db` for a match (that part admittedly an ugly hack!), and if one is found use that as the overriding hostname for the output. 
