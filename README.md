Update `iptables` to agave connection hosts
========================
This repository pulls contains scripts to pull ip lists from the [Agave Platform|http://agaveapi.co] and [Pingdom|http://pingdom.com] and add appropriate rules to the `iptables` firewalls on the host where these scripts are run.

These scripts are best run as daily cron jobs. Examples example:

    32 2 * * * /root/allow-agave-connections/update_agave_connectors.sh 22 1247 > /dev/null 2>&1
    32 2 * * * /root/allow-agave-connections/update_pingdom_probes.sh 80 443 > /dev/null 2>&1

## update_agave_connectors.sh

When running this script, pass it the ports you would like to be allowed to agave hosts. The key to remember when running this script is that Agave will need access the ports used by the data and login protocols you used when registering this host as a system. For example, if you registered this host specifying a data protocol of SFTP and a login protocol of SSH, then you would just use `22` as the port. However, if you used GSISSH and GridFTP, then you would need use `2222`, `2811`, `50000-51000` to cover both the data and control channels used by gridftp and the default gsissh port.  If you are running on non-standard ports, change the above accordingly.

    32 2 * * * /root/allow-agave-connections/update_agave_connectors.sh 22 > /dev/null 2>&1

> This repository was adapted from [https://github.com/etcet/csf-allow-pingdom-probes/blob/master/update_pingdom_probes.sh]
