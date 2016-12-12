Zabbix HP MSA P2000 G3
=========================

# Credits

I got it from Mr. Emir Imamagic @ https://www.zabbix.com/forum/showthread.php?t=26572

# Installation

* Put the hp-msa.pl file in the directory entered in the [ExternalScripts directive](https://www.zabbix.com/documentation/3.0/manual/config/items/itemtypes/external) of your [zabbix-server.conf](https://www.zabbix.com/documentation/3.0/manual/appendix/config/zabbix_server), /usr/local/share/zabbix/externalscripts for default.
* Then: `chmod +x /usr/local/share/zabbix/externalscripts/hp-msa.pl` if you want to run it without the perl command.
* [Import the xml template into Zabbix via GUI](https://www.zabbix.com/documentation/3.0/manual/web_interface/frontend_sections/configuration/templates).

# Configuration

Change these variables:

```perl
my $USERNAME = "manage"; # your HP MSA P2000 username
my $PASSWORD = "\\!manage"; # your HP MSA P2000 password
```

# Usage

```sh
perl hp-msa.pl <HOSTNAME> [lld|stats]
```

I tested in Zabbix 3.0 on CentOS 7

# Description of the original thread

2012-06-07

Hello,

I attached script and Zabbix template for transfer rates and IOPS for HP P2000 G3 storage system. I used LLD so this solution can be used only in Zabbix 2.0.
For earlier versions it is possible to use statistic gathering & reporting part, but one needs to manually create templates.

Script (hp-msa.pl) uses XML API and it is based on the example provided in "HP P2000 G3 MSA System CLI Reference Guide". Same script is used for LLD and reporting values as "Zabbix trappers". Execute hp-msa.pl to see usage. Unfortunately script does not have decent error/timeout handling, it is in my TODO list.

Template uses LLD to discover all:
controllers
virtual disks
volumes

Discovery item (HP Entities Discovery) uses {HOST.CONN} to connect to the storage system. Statistics gathering item (HP P2000 Sensor) uses {HOST.DNS1} for connecting and value reporting. Make sure that storage host has these two properly configured.

Script execution time is ~10s so one needs to increase Zabbix server config file, e.g.:
Timeout=30

Big thanks to Zabbix team, LLD makes template generation soo much easier.

Best regards,
Emir Imamagic

Font: https://www.zabbix.com/forum/showthread.php?t=26572
