#!/bin/bash
# Update the pingdom firewall rules based on their feed

# RSS feed where the current list of pingdom hosts lives.
PINGDOM_SERVER_FEED='https://www.pingdom.com/rss/probe_servers.xml'

# Location of the cache directory for the pingdom ip addresses
PINGDOM_IP_CACHE_DIR=pingdom

# Uncomment to force the script to run
#FORCE_UPDATE=1

# Uncomment to enabled debug output
FORCE_DEBUG=1

# Uncomment to print actual iptable rules
#FORCE_TRACE=1

# Uncomment to print the list of ip addresses and exist
#FETCH_ONLY=1

######################################################
# DO NOT EDIT BELOW THIS LINE
######################################################

# protocols passed in as arguments to the script
PROTOCOL_PORTS=$@

# ensure at least one script is entered
if [[ -z "$PROTOCOL_PORTS" ]]; then
	echo "ERROR: Please specify one or more ports to allow access from Agave servers" 1>&2
	exit 1;
else
	PROTOCOL_PORTS=("$@")
fi

echo "Running script to allow Agave servers access to this host on port ${PROTOCOL_PORTS}"

if [[ ! -e "$PINGDOM_IP_CACHE_DIR" ]]; then
	mkdir -p $PINGDOM_IP_CACHE_DIR
fi

(($FORCE_DEBUG)) && echo "Saving pingdom server ip cache to $PINGDOM_IP_CACHE_DIR/pingdom_ips"

# get pingdom ips from their rss feed
(($FORCE_DEBUG)) && echo "Fetching server list from $PINGDOM_SERVER_FEED"
wget $PINGDOM_SERVER_FEED -O $PINGDOM_IP_CACHE_DIR/probe_servers.xml -o /dev/null
if (("$FETCH_ONLY")); then
	cat $PINGDOM_IP_CACHE_DIR/probe_servers.xml | grep IP | sed -e 's/.*IP: //g' | sed -e 's/; Host.*//g' | grep -v IP
	exit 0
else
	# rotate pingdom ip list (keep 8 days)
	LIST=$(ls -r $PINGDOM_IP_CACHE_DIR/pingdom_ips*);
	for i in $LIST; do
		# get index of file
		INDEX=$(ls $i | cut -d"." -f 2)

		# if there's no index, rename to pingdom_ips.0
		if [ $INDEX = "$PINGDOM_IP_CACHE_DIR/pingdom_ips" ]; then
			NEW=$INDEX.0
			mv $i $NEW
		# remove files with index > 6 (keep 8 files)
		elif [ $INDEX -gt 6 ]; then
			rm $i
		# increment index for all other files
		else
			BASE=$(ls $i | cut -d"." -f 1)
			NEW=$BASE.$(($INDEX+1))
			mv $i $NEW
		fi
	done

	cat $PINGDOM_IP_CACHE_DIR/probe_servers.xml | grep IP | sed -e 's/.*IP: //g' | sed -e 's/; Host.*//g' | grep -v IP > $PINGDOM_IP_CACHE_DIR/pingdom_ips
fi

# if old lists do not exist, just allow all ips in the feed on each of the supplied $PROTOCOL_PORTS
if [ ! -f $PINGDOM_IP_CACHE_DIR/pingdom_ips.0 ]; then
	# iterate over all ip addresses
	for j in `cat $PINGDOM_IP_CACHE_DIR/pingdom_ips`; do
		# add a rule for each protocol port given as an argument to this script
		(($FORCE_DEBUG)) && echo "Allowing access to $j on ${PROTOCOL_PORTS[@]}"
		for p in "${PROTOCOL_PORTS[@]}"; do
			(($FORCE_TRACE)) && echo "iptables -A INPUT -p tcp -s $j -m tcp --dport $p -j ACCEPT"
			iptables -A INPUT -p tcp -s $j -m tcp --dport $p -j ACCEPT
		done
	done
else
	# if there any differences between previous and current list, synch up the ip list
	if [[ -n "$FORCE_UPDATE" ]] || [[ -n $(diff -q $PINGDOM_IP_CACHE_DIR/pingdom_ips $PINGDOM_IP_CACHE_DIR/pingdom_ips.0) ]]; then

		# get a list of just the removed ip addresses
		REMOVED_IP=$(diff --changed-group-format='%>' --unchanged-group-format='' $PINGDOM_IP_CACHE_DIR/pingdom_ips $PINGDOM_IP_CACHE_DIR/pingdom_ips.0)
		if [[ -n "$REMOVED_IP" ]] || (("$FORCE_UPDATE")); then
			for i in `echo $REMOVED_IP`; do
				# add a rule for each port given as an argument to this script
				(($FORCE_DEBUG)) && echo "Revoking access to $i on ${PROTOCOL_PORTS[@]}"
				for p in "${PROTOCOL_PORTS[@]}"; do
					(($FORCE_TRACE)) && echo "iptables -A INPUT -p tcp -s $i -m tcp --dport $p -j DROP"
					iptables -A INPUT -p tcp -s $i -m tcp --dport $p -j DROP
				done
			done
		fi

		# get a list of just the added ip addresses
		ADDED_IP=$(diff --changed-group-format='%>' --unchanged-group-format='' $PINGDOM_IP_CACHE_DIR/pingdom_ips.0 $PINGDOM_IP_CACHE_DIR/pingdom_ips)
		if [[ -n "$ADDED_IP" ]] || (("$FORCE_UPDATE")); then
			# add a rule for each ip address added
			for j in `cat $PINGDOM_IP_CACHE_DIR/pingdom_ips`; do
				# add a rule for each port given as an argument to this script
				(($FORCE_DEBUG)) && echo "Allowing access to $j on ${PROTOCOL_PORTS[@]}"
				for p in "${PROTOCOL_PORTS[@]}"; do
					(($FORCE_TRACE)) && echo "iptables -A INPUT -p tcp -s $j -m tcp --dport $p -j ACCEPT"
					iptables -A INPUT -p tcp -s $j -m tcp --dport $p -j ACCEPT
				done
			done
		fi
	fi
fi
