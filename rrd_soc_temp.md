Store internal temperature to Round Robin Database
=====
The script is supposed to be used under cron. For debuging purposes it is supposed to be run in simulation mode. The script logs temperatures and other messages into the syslog.

Name
=====
**rrd\_soc\_temp.sh** - Record system temperature to Round Robin Database

Synopsis
=====
    rrd_soc_temp.sh [OPTION [ARG]] [RRD_file]

Description
=====
Script measures internal temperature of the CPU and stores it into RRD.
- The current temperature is read from `/sys/class/thermal/thermal_zone0/temp`.
- Script has to be run under root privileges (sudo ...).
- Script is supposed to run under cron.
- Script logs to `user.log`.
- Script may write its working status into a status (tick) file if defined, what may   be considered as a monitoring heartbeat of the script especially then in normal conditions   it produces no output.
- Status file should be located in the temporary file system (e.g., in the folder `/run`) in order to reduce writes to the SD card.
- All essential parameters are defined in the section of configuration parameters. Their description is provided locally. Script can be configured by changing values of them.
- Configuration parameters in the script can be overriden by the corresponding ones in a configuration file declared in the command line.
- If RRD file does not exist yet, the script creates one.


Options and arguments
=====
    -h                 help: show this help and exit
    -s                 simulate: perform dry run without writing to Google Analytics
    -V                 Version: show version information and exit
    -c                 configs: print listing of all configuration parameters
    -l log_level       logging: level of logging intensity to syslog
                       0=none, 1=errors (default), 2=warnings, 3=info, 4=full
    -o verbose_level   output: level of verbosity
                       0=none, 1=errors (default), 2=mails, 3=info, 4=functions, 5=full
    -m                 mailing: display all processing messages; alias for '-o2'
    -v                 verbose: display all processing messages; alias for '-o5'
    -f config_file     file: configuration file to be used
    -t status_file     tick: status file to be used
    -T                 Temperature: Display current SoC temperature


Configuration
=====
The configuration is predefined by the values of configuration parameters in the script's section **\_config**. Each of configuration parameters begins with the prefix **CONFIG\_**. Here are some of the most interesting ones. Change them reasonably and if you know, what you are doing.

The configuration parameters can be overriden by corresponding ones, if they are present in the configuration file declared by an argument of the option "**-f**". Finally some of them may be overriden by respective command line options. So the precedence priority of configuration parameters is as follows where the latest is valid:

- Script
- Command line option
- Configuration file

#### CONFIG\_rrd\_file
This parameter defines the database file for the RRDtool, to which the data should be written.

#### CONFIG\_level\_logging
This parameter defines the level or intensity of logging to system log **user.log**. It takes an integer parameter from the following list

- `0` ... no logging to system log
- `1` ... logging just error messages
- `2` ... logging warning messages as well as all messages from previous logging levels
- `3` ... logging information messages as well as all messages from previous logging levels
- `4` ... logging all possible messages that can be logged

#### CONFIG\_level\_verbose
This parameter defines the level of verbosity to the console. It takes an integer parameter from the following list

- `0` ... no messages
- `1` ... just error messages
- `2` ... messages for emailing as well as all messages from previous verbose levels
- `3` ... information messages as well as all messages from previous verbose levels
- `4` ... messages from essetial functions as well as all messages from previous verbose levels
- `5` ... all possible messages

#### CONFIG\_config
The path to a configuration file, which can substitute command line options and parameters. It is read in the script as a shell script so you can abuse that fact if you so want to. It should contain just configuration variables assignment that you want to overide in the form

    CONFIG_param=value

The configuration file should not contain any programmatic code in order not to change the behaviour of the script.

License
=====
This script is free software; you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation; either version 2 of the License, or (at your option) any later version. 