#!/bin/bash
# Update the agave firewall rules based on their feed

# RSS feed where the current list of agave hosts lives.
AGAVE_SERVER_FEED='http://agaveapi.co/server-feed/'

# Location of the cache directory for the agave ip addresses
AGAVE_IP_CACHE_DIR=agave

# Uncomment to force the script to run
#FORCE_UPDATE=1

# Uncomment to enabled debug output
#FORCE_DEBUG=1

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

if [[ ! -e "$AGAVE_IP_CACHE_DIR" ]]; then
	mkdir -p $AGAVE_IP_CACHE_DIR
fi

(($FORCE_DEBUG)) && echo "Saving agave server ip cache to $AGAVE_IP_CACHE_DIR/agave_ips"

# get agave ips from their rss feed
(($FORCE_DEBUG)) && echo "Fetching server list from $AGAVE_SERVER_FEED"
wget $AGAVE_SERVER_FEED -O $AGAVE_IP_CACHE_DIR/agave_connector_servers.xml -o /dev/null
if [[ -n "$FETCH_ONLY" ]]; then
	cat $AGAVE_IP_CACHE_DIR/agave_connector_servers.xml | grep '<title>' | sed -e 's/<title>//g' | sed -e 's/<\/title>//g' | sed -e 's/    //g' | grep -v "Listing"
	exit 0
else
	# rotate agave ip list (keep 8 days)
	#
	LIST=$(ls -r $AGAVE_IP_CACHE_DIR/agave_ips*);
	for i in $LIST; do
		# get index of file
		INDEX=$(ls $i | cut -d"." -f 2)

		# if there's no index, rename to agave_ips.0
		if [ $INDEX = "$AGAVE_IP_CACHE_DIR/agave_ips" ]; then
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

	cat $AGAVE_IP_CACHE_DIR/agave_connector_servers.xml | grep '<title>' | sed -e 's/<title>//g' | sed -e 's/<\/title>//g' | sed -e 's/    //g' | grep -v "Listing" > $AGAVE_IP_CACHE_DIR/agave_ips
fi

# if old lists do not exist, just allow all ips in the feed on each of the supplied $PROTOCOL_PORTS
if [ ! -f $AGAVE_IP_CACHE_DIR/agave_ips.0 ]; then
	# iterate over all ip addresses
	for j in `cat $AGAVE_IP_CACHE_DIR/agave_ips`; do
		# add a rule for each protocol port given as an argument to this script
		(($FORCE_DEBUG)) && echo "Allowing access to $j on ${PROTOCOL_PORTS[@]}"
		for p in "${PROTOCOL_PORTS[@]}"; do
			(($FORCE_TRACE)) && echo "iptables -A INPUT -p tcp -s $j -m tcp --dport $p -j ACCEPT"
			iptables -A INPUT -p tcp -s $j -m tcp --dport $p -j ACCEPT
		done
	done
else
	# if there any differences between previous and current list, synch up the ip list
	if [[ -n "$FORCE_UPDATE" ]] || [[ -n $(diff -q $AGAVE_IP_CACHE_DIR/agave_ips $AGAVE_IP_CACHE_DIR/agave_ips.0) ]]; then

		# get a list of just the removed ip addresses
		REMOVED_IP=$(diff --changed-group-format='%>' --unchanged-group-format='' $AGAVE_IP_CACHE_DIR/agave_ips $AGAVE_IP_CACHE_DIR/agave_ips.0)
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
		ADDED_IP=$(diff --changed-group-format='%>' --unchanged-group-format='' $AGAVE_IP_CACHE_DIR/agave_ips.0 $AGAVE_IP_CACHE_DIR/agave_ips)
		if [[ -n "$ADDED_IP" ]] || (("$FORCE_UPDATE")); then
			# add a rule for each ip address added
			for j in `cat $AGAVE_IP_CACHE_DIR/agave_ips`; do
				# add a rule for each port given as an argument to this script
				(($FORCE_DEBUG)) && echo "Allowing access to $j on ${PROTOCOL_PORTS[@]}"
				for p in "${PROTOCOL_PORTS[@]}"; do
					(($FORCE_TRACE)) && echo "iptables -A INPUT -p tcp -s $j -m tcp --dport $p -j ACCEPT"
					iptables -A INPUT -p tcp -s $j -m tcp --dport $p -j ACCEPT
				done
			done

			(($FORCE_DEBUG)) && echo "Allowing outbound traffics to established connectionsfrom Agave hosts"
			(($FORCE_TRACE)) && echo "iptables -I INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT"
			iptables -I INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
		fi
	fi
fi
