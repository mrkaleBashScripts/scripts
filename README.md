Scripts for microcomputers Pi
=====
This project contains a set of bash scripts, which are useful for backing up, controlling and maintaining the operating system. They usually do not relate to each other and should be considered as standalone ones. On the other hand, they all serve for better operating Pi computer like Raspberry Pi, Orange Pi, Nano Pi, etc.

Each of scripts has got its own description (.md) file with details about its usage and purpose.

scripts_lib.sh
=====
The script is supposed to be a library for all remaining working scripts. It should be located in the same folder as respective script either directly or as a symbolic link.

check_temp.sh
=====
The script checks the internal temperature of the SoC. If the temperature exceeds a warning limit as a percentage of maximal limit written in the system, it outputs an alert message. If the temperature exceeds a shutdown limit as a percentage of maximal limit, it outputs a fatal message and shuts down the system. 

check_dbs.sh
=====
The script is supposed to check database tables of type *MyISAM*, *InnoDB*, and *Archive* in MySQL databases. By default the script outputs just the error messages about corrupted tables, so that it is suitable for periodic checking under cron.

rrd_soc_temp.sh
=====
The script reads system temperature and stores it to a Round Robin Database. If it does not exist yet, the script creates one.

rrd_graph_temp.sh
=====
The script reads Round Robin Database with system temperature and creates pictures with graphs and locate them to a web server document folder for visualizing them.

